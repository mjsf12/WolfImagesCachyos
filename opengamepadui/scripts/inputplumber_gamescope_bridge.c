/* Forward InputPlumber's evdev mouse/keyboard targets to Gamescope's EIS seat. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <libei.h>
#include <linux/input.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define MOUSE_NAME "InputPlumber Mouse"
#define KEYBOARD_NAME "InputPlumber Keyboard"
#define DEFAULT_EIS_SOCKET "gamescope-0-ei"

enum source_kind {
    SOURCE_MOUSE,
    SOURCE_KEYBOARD,
};

struct input_source {
    int fd;
    enum source_kind kind;
    char path[256];
};

struct pending_pointer {
    double dx;
    double dy;
    int32_t scroll_x;
    int32_t scroll_y;
    bool dirty;
};

struct bridge {
    struct ei *ei;
    struct ei_device *device;
    bool emulating;
    uint32_t sequence;
    struct pending_pointer pointer;
};

static void log_message(const char *message)
{
    fprintf(stderr, "[inputplumber-gamescope-bridge] %s\n", message);
    fflush(stderr);
}

static bool target_name_matches(enum source_kind kind, const char *name)
{
    return strcmp(name, kind == SOURCE_MOUSE ? MOUSE_NAME : KEYBOARD_NAME) == 0;
}

static int read_device_name(const char *event_path, char *name, size_t size)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/device/name", event_path);
    FILE *file = fopen(path, "r");
    if (!file)
        return -errno;
    if (!fgets(name, (int)size, file)) {
        int error = errno ? -errno : -EIO;
        fclose(file);
        return error;
    }
    fclose(file);
    name[strcspn(name, "\r\n")] = '\0';
    return 0;
}

static int open_target(enum source_kind kind, struct input_source *source)
{
    glob_t paths = {0};
    int result = glob("/sys/class/input/event*", 0, NULL, &paths);
    if (result != 0)
        return result == GLOB_NOMATCH ? -ENOENT : -EIO;

    int fd = -ENOENT;
    for (size_t index = 0; index < paths.gl_pathc; index++) {
        char name[256];
        if (read_device_name(paths.gl_pathv[index], name, sizeof(name)) != 0)
            continue;
        if (!target_name_matches(kind, name))
            continue;

        const char *event_name = strrchr(paths.gl_pathv[index], '/');
        if (!event_name)
            continue;
        snprintf(source->path, sizeof(source->path), "/dev/input/%s", event_name + 1);
        fd = open(source->path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0) {
            source->fd = fd;
            source->kind = kind;
            break;
        }
        fd = -errno;
    }
    globfree(&paths);
    return fd;
}

static void close_source(struct input_source *source)
{
    if (source->fd >= 0)
        close(source->fd);
    source->fd = -1;
}

static void release_ei_device(struct bridge *bridge)
{
    bridge->emulating = false;
    if (bridge->device) {
        ei_device_unref(bridge->device);
        bridge->device = NULL;
    }
}

static bool device_has_bridge_capabilities(struct ei_device *device)
{
    return ei_device_has_capability(device, EI_DEVICE_CAP_POINTER) &&
           ei_device_has_capability(device, EI_DEVICE_CAP_BUTTON) &&
           ei_device_has_capability(device, EI_DEVICE_CAP_SCROLL) &&
           ei_device_has_capability(device, EI_DEVICE_CAP_KEYBOARD);
}

static void log_device_capabilities(struct ei_device *device)
{
    fprintf(
        stderr,
        "[inputplumber-gamescope-bridge] EIS capabilities: "
        "pointer=%d button=%d scroll=%d keyboard=%d\n",
        ei_device_has_capability(device, EI_DEVICE_CAP_POINTER),
        ei_device_has_capability(device, EI_DEVICE_CAP_BUTTON),
        ei_device_has_capability(device, EI_DEVICE_CAP_SCROLL),
        ei_device_has_capability(device, EI_DEVICE_CAP_KEYBOARD)
    );
    fflush(stderr);
}

static int dispatch_ei(struct bridge *bridge)
{
    ei_dispatch(bridge->ei);
    while (true) {
        struct ei_event *event = ei_get_event(bridge->ei);
        if (!event)
            break;

        enum ei_event_type type = ei_event_get_type(event);
        switch (type) {
        case EI_EVENT_CONNECT:
            break;
        case EI_EVENT_DISCONNECT:
            ei_event_unref(event);
            return -ECONNRESET;
        case EI_EVENT_SEAT_ADDED:
            ei_seat_bind_capabilities(
                ei_event_get_seat(event),
                EI_DEVICE_CAP_POINTER,
                EI_DEVICE_CAP_BUTTON,
                EI_DEVICE_CAP_SCROLL,
                EI_DEVICE_CAP_KEYBOARD,
                NULL
            );
            break;
        case EI_EVENT_DEVICE_ADDED: {
            struct ei_device *device = ei_event_get_device(event);
            log_device_capabilities(device);
            if (!bridge->device && device_has_bridge_capabilities(device))
                bridge->device = ei_device_ref(device);
            break;
        }
        case EI_EVENT_DEVICE_RESUMED:
            if (ei_event_get_device(event) == bridge->device) {
                ei_device_start_emulating(bridge->device, ++bridge->sequence);
                bridge->emulating = true;
                log_message("connected to Gamescope EIS input seat");
            }
            break;
        case EI_EVENT_DEVICE_PAUSED:
            if (ei_event_get_device(event) == bridge->device)
                bridge->emulating = false;
            break;
        case EI_EVENT_DEVICE_REMOVED:
            if (ei_event_get_device(event) == bridge->device)
                release_ei_device(bridge);
            break;
        default:
            break;
        }
        ei_event_unref(event);
    }
    return 0;
}

static void flush_pointer(struct bridge *bridge)
{
    struct pending_pointer *pointer = &bridge->pointer;
    if (pointer->dx != 0.0 || pointer->dy != 0.0)
        ei_device_pointer_motion(bridge->device, pointer->dx, pointer->dy);
    if (pointer->scroll_x != 0 || pointer->scroll_y != 0)
        ei_device_scroll_discrete(
            bridge->device,
            pointer->scroll_x,
            pointer->scroll_y
        );
    if (pointer->dirty)
        ei_device_frame(bridge->device, ei_now(bridge->ei));
    memset(pointer, 0, sizeof(*pointer));
}

static void handle_mouse(struct bridge *bridge, const struct input_event *event)
{
    if (event->type == EV_REL) {
        switch (event->code) {
        case REL_X:
            bridge->pointer.dx += event->value;
            bridge->pointer.dirty = true;
            break;
        case REL_Y:
            bridge->pointer.dy += event->value;
            bridge->pointer.dirty = true;
            break;
        case REL_HWHEEL:
            bridge->pointer.scroll_x -= event->value * 120;
            bridge->pointer.dirty = true;
            break;
        case REL_WHEEL:
            bridge->pointer.scroll_y -= event->value * 120;
            bridge->pointer.dirty = true;
            break;
        default:
            break;
        }
        return;
    }

    if (event->type == EV_KEY && event->value != 2) {
        ei_device_button_button(bridge->device, event->code, event->value != 0);
        bridge->pointer.dirty = true;
        return;
    }

    if (event->type == EV_SYN && event->code == SYN_REPORT)
        flush_pointer(bridge);
}

static void handle_keyboard(struct bridge *bridge, const struct input_event *event)
{
    if (event->type == EV_KEY && event->value != 2) {
        ei_device_keyboard_key(bridge->device, event->code, event->value != 0);
        bridge->pointer.dirty = true;
        return;
    }
    if (event->type == EV_SYN && event->code == SYN_REPORT)
        flush_pointer(bridge);
}

static int read_source(struct bridge *bridge, struct input_source *source)
{
    struct input_event events[64];
    ssize_t bytes = read(source->fd, events, sizeof(events));
    if (bytes < 0)
        return errno == EAGAIN || errno == EINTR ? 0 : -errno;
    if (bytes == 0)
        return -ENODEV;

    size_t count = (size_t)bytes / sizeof(events[0]);
    for (size_t index = 0; index < count; index++) {
        if (!bridge->emulating)
            continue;
        if (source->kind == SOURCE_MOUSE)
            handle_mouse(bridge, &events[index]);
        else
            handle_keyboard(bridge, &events[index]);
    }
    return 0;
}

static int run_bridge(const char *socket_name)
{
    struct input_source mouse = {.fd = -1, .kind = SOURCE_MOUSE};
    struct input_source keyboard = {.fd = -1, .kind = SOURCE_KEYBOARD};
    int result = open_target(SOURCE_MOUSE, &mouse);
    if (result < 0)
        return result;
    result = open_target(SOURCE_KEYBOARD, &keyboard);
    if (result < 0) {
        close_source(&mouse);
        return result;
    }

    struct bridge bridge = {0};
    bridge.ei = ei_new_sender(NULL);
    if (!bridge.ei) {
        result = -ENOMEM;
        goto finished;
    }
    ei_configure_name(bridge.ei, "InputPlumber Gamescope Bridge");
    result = ei_setup_backend_socket(bridge.ei, socket_name);
    if (result != 0)
        goto finished;

    struct pollfd descriptors[] = {
        {.fd = ei_get_fd(bridge.ei), .events = POLLIN},
        {.fd = mouse.fd, .events = POLLIN},
        {.fd = keyboard.fd, .events = POLLIN},
    };
    while (true) {
        int ready = poll(descriptors, 3, -1);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            result = -errno;
            break;
        }
        if (descriptors[0].revents & (POLLIN | POLLERR | POLLHUP)) {
            result = dispatch_ei(&bridge);
            if (result < 0)
                break;
        }
        if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) {
            result = -ENODEV;
            break;
        }
        if (descriptors[2].revents & (POLLERR | POLLHUP | POLLNVAL)) {
            result = -ENODEV;
            break;
        }
        if (descriptors[1].revents & POLLIN) {
            result = read_source(&bridge, &mouse);
            if (result < 0)
                break;
        }
        if (descriptors[2].revents & POLLIN) {
            result = read_source(&bridge, &keyboard);
            if (result < 0)
                break;
        }
    }

finished:
    release_ei_device(&bridge);
    if (bridge.ei)
        ei_unref(bridge.ei);
    close_source(&mouse);
    close_source(&keyboard);
    return result;
}

static int self_test(void)
{
    if (!target_name_matches(SOURCE_MOUSE, MOUSE_NAME))
        return 1;
    if (!target_name_matches(SOURCE_KEYBOARD, KEYBOARD_NAME))
        return 1;
    if (target_name_matches(SOURCE_MOUSE, KEYBOARD_NAME))
        return 1;

    struct pending_pointer pointer = {0};
    pointer.dx += 4;
    pointer.dy -= 7;
    pointer.scroll_y -= 120;
    if (pointer.dx != 4 || pointer.dy != -7 || pointer.scroll_y != -120)
        return 1;
    puts("inputplumber-gamescope-bridge self-test passed");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0)
        return self_test();

    const char *socket_name = getenv("LIBEI_SOCKET");
    if (!socket_name || !socket_name[0])
        socket_name = argc > 1 ? argv[1] : DEFAULT_EIS_SOCKET;

    log_message("waiting for InputPlumber targets and Gamescope EIS socket");
    while (true) {
        int result = run_bridge(socket_name);
        if (result == 0)
            return 0;
        sleep(1);
    }
}
