# Wolf Images - CachyOS

Imagens Docker alternativas para o [Wolf](https://github.com/games-on-whales/wolf) construídas sobre o [CachyOS](https://cachyos.org/), uma distribuição baseada em Arch Linux otimizada para performance.

## Sobre

Este projeto fornece imagens Docker personalizadas como alternativa às imagens padrão do [games-on-whales/gow](https://github.com/games-on-whales/gow). Enquanto as imagens originais são baseadas em distribuições genéricas, estas imagens aproveitam as otimizações do CachyOS para potencialmente melhor desempenho em workloads de jogos e multimídia.

### Projetos Relacionados

- **[Wolf](https://github.com/games-on-whales/wolf)** - Servidor de streaming de jogos compatível com Moonlight
- **[games-on-whales/gow](https://github.com/games-on-whales/gow)** - Imagens Docker originais nas quais este projeto se baseia

## Guia de Configuração

Este documento explica como configurar o `newImages` para executar aplicativos dentro de containers Docker com passagem de GPU e acesso a dispositivos.

## Estrutura Básica

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'Nome do App'

    [profiles.apps.runner]
    # configuração do container Docker
```

## Opções de Configuração

### Nível App

| Campo | Tipo | Descrição |
|-------|------|-------------|
| `icon_png_path` | string | Caminho para o ícone do app (vazio = padrão) |
| `start_virtual_compositor` | bool | Inicia um compositor virtual (Wayland/X11) |
| `title` | string | Nome de exibição do app |

### Nível Runner

| Campo | Tipo | Descrição |
|-------|------|-------------|
| `base_create_json` | string | JSON bruto da API Docker para criação do container |
| `devices` | array | Mapeamentos de dispositivos (ex: `/dev/ntsync`) |
| `env` | array | Variáveis de ambiente |
| `image` | string | Nome da imagem Docker |
| `mounts` | array | Montagens de volume (host:container:modo) |
| `name` | string | Identificador do nome do container |
| `ports` | array | Mapeamentos de porta (vazio = nenhum) |
| `type` | string | Tipo do runner (`docker`) |

## Exemplo Completo

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'Heroic (CachyOS)'

    [profiles.apps.runner]
    base_create_json = '''{
  "HostConfig": {
    "IpcMode": "host",
    "Privileged": false,
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE"],
    "CpusetCpus": "0-7,16-23",
    "Devices": [
    {
        "PathOnHost": "/dev/ntsync",
        "PathInContainer": "/dev/ntsync",
        "CgroupPermissions": "rwm"
    }
    ],
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
'''
    devices = [ '/dev/ntsync:/dev/ntsync:rwm' ]
    env = [
        'RUN_SWAY=1',
        'GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*',
        'LANG=pt_BR.UTF-8',
        'LANGUAGE=pt_BR:pt',
        'LC_ALL=pt_BR.UTF-8',
        'XKB_DEFAULT_LAYOUT=br',
        'XKB_DEFAULT_MODEL=pc105',
        'XKB_DEFAULT_VARIANT=abnt2'
    ]
    image = 'gow/cachyos-heroic'
    mounts = [
        '/home/mjsf12/.config/heroic:/home/gow/.config/heroic:rw',
        '/home/mjsf12/Games:/home/gow/Games:rw'
    ]
    name = 'CachyOSHeroic'
    ports = []
    type = 'docker'
```

## Notas Importantes

### Afinidade de CPU
- `CpusetCpus` fixa os containers a cores específicos
- Exemplo: `"0-7,16-23"` usa os cores 0-7 e 16-23 (típico para hyperthreading)

### Passagem de Dispositivos
- Adicione dispositivos tanto em `base_create_json.Devices` QUANTO no array `devices`
- Formato: `/dev/ntsync:/dev/ntsync:rwm`

### Compositor
- Defina `start_virtual_compositor = true` para apps com GUI
- `RUN_SWAY=1` no env ativa o compositor Sway dentro do container

### Modo XFCE Desktop (Pegasus)
- Defina `RUN_XFCE=1` no env para iniciar um XFCE completo (Thunar, terminal, mousepad, painel, gerenciador de janelas)
- Roda direto no XWayland do compositor virtual — sem Sway envolvido
- Útil para configurar o sistema, instalar jogos ou ajustar emuladores
- A sessão encerra quando você desloga do XFCE

```toml
# No config.toml do Wolf
env = [ 'RUN_XFCE=1' ]
```

### Localidade/Teclado
- Defina `LANG`, `LANGUAGE`, `LC_ALL` para locale
- Defina `XKB_*` para layout de teclado (exemplo: ABNT2 brasileiro)

## Build de Imagens

O build segue uma estrutura hierárquica:

```
base (NewImages/base)
   ├── app (NewImages/heroic, NewImages/firefox, etc.)
   └── pegasus
       └── opengamepadui
```

### Build da Imagem Base Primeiro

```bash
# Build da imagem base
docker build -t gow/cachyos-base NewImages/base
```

### Build da Imagem do App

```bash
# Build do app usando a base
docker build -t gow/cachyos-heroic \
  --build-arg BASE_IMAGE=gow/cachyos-base \
  NewImages/heroic
```

A imagem `pegasus` herda da `base` diretamente (não do `heroic`) e inclui todos os frontends de jogos:

```bash
docker build -t gow/cachyos-pegasus \
  --build-arg BASE_IMAGE=gow/cachyos-base \
  NewImages/pegasus
```

A imagem `opengamepadui` herda todos os pacotes do Pegasus, instala
`opengamepadui-bin` com todas as dependências opcionais via `paru` e inicia a
sessão oficial sobre Gamescope:

```bash
docker build -t gow/cachyos-opengamepadui \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus \
  NewImages/opengamepadui
```

### Build de Todos os NewImages

```bash
# Base
docker build -t gow/cachyos-base NewImages/base

# Apps
docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
docker build -t gow/cachyos-firefox --build-arg BASE_IMAGE=gow/cachyos-base NewImages/firefox
docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-base NewImages/pegasus
docker build -t gow/cachyos-opengamepadui --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus NewImages/opengamepadui
```

## Fluxo Completo

```bash
# 1. Build da base
docker build -t gow/cachyos-base NewImages/base

# 2. Build do pegasus (inclui frontends de jogos + modo XFCE)
docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-base NewImages/pegasus

# 3. Use no config.toml do Wolf
[[profiles.apps]]
    title = 'Pegasus (CachyOS)'
    [profiles.apps.runner]
    image = 'gow/cachyos-pegasus'
    type = 'docker'
    ...
```

### OpenGamepadUI com Gamescope

O runbook técnico completo, com arquitetura, histórico das correções, patches,
plugins, servidor e diagnóstico, está em
[`opengamepadui/CONTINUIDADE-E-DEBUG.md`](opengamepadui/CONTINUIDADE-E-DEBUG.md).

O OpenGamepadUI usa Gamescope por padrão; não defina `RUN_SWAY` nesse perfil.
A imagem instala uma compilação corrigida do InputPlumber 0.78.0 que:

- reconhece os controles virtuais `Wolf X-Box One`, `Wolf PS5`,
  `Wolf DualSense`, `Wolf Nintendo` e o sensor de movimento;
- cria o observador de `/dev/input` antes que o Wolf conecte o controle;
- adiciona o usuário dinâmico da sessão ao grupo autorizado pelo polkit do
  InputPlumber antes do login final, liberando mudanças de rota, perfil, alvos
  e mouse pelo D-Bus;
- toma posse exclusiva do controle source do Wolf e entrega ao OpenGamepadUI
  eventos D-Bus; jogos enxergam somente o target Xbox criado pelo InputPlumber;
- ativa o modo de interceptação D-Bus quando um controle composto nasce em
  modo `0`, sem impedir que o OpenGamepadUI use o modo de jogo `1`.

O build também corrige a descoberta de janelas do OpenGamepadUI 0.46.0. O
Gamescope publica janelas X11 focáveis em blocos `[window_id, app_id, pid]`; o
launcher corrigido usa esse AppId como fallback quando Bottles, Heroic, Lutris
ou outro launcher intermediário remove `OGUI_ID` do processo do jogo. Ao fechar
o último jogo, o plugin `Wolf Gamescope Session` desativa `STEAM_OVERLAY` e
restaura a lista de baselayer do Gamescope; isso evita que o menu continue
transparente sobre uma tela preta. Os patches antigos desse ciclo estão
preservados como backup, mas não são aplicados junto com o plugin.

A imagem também instala o plugin `Wolf Desktop Input`. Para controles genéricos
do Moonlight, ele converte `Start + Select` em um botão Guide virtual. Soltar o
atalho abre o menu principal; `Start + Select + A` abre a barra rápida e
`Start + Select + X` alterna entre o perfil normal e o modo desktop. No modo
desktop, o analógico direito move o ponteiro, `A`/RT fazem clique esquerdo,
`B`/LT fazem clique direito e os bumpers rolam a página. O perfil anterior do
jogo é restaurado ao sair do modo mouse. A barra rápida permite alterar o modo,
o atalho genérico, a ativação automática para launchers e a velocidade do
ponteiro. Cada mudança de rota é confirmada relendo a propriedade D-Bus real;
assim uma operação negada silenciosamente não é mais registrada como sucesso.
Trinta e seis testes validam atalhos, rotas, transição para jogos,
serialização de perfil, falha de autorização e o perfil desktop. O plugin
registra sua página procedural com um título explícito na barra rápida, evitando
a busca legada insegura por `SectionLabel` do OpenGamepadUI 0.46.0.

A sessão também grava propriedades correlacionadas do InputPlumber, sinais
D-Bus, eventos evdev relevantes da origem e dos alvos e movimentos do ponteiro
X11 em `~/.local/state/opengamepadui/wolf-input-trace.jsonl`. As transações do
plugin usam o marcador `[trace]` nos logs do contêiner. Defina
`WOLF_INPUT_DIAGNOSTICS=0` para desativar o gravador externo depois do debug. Por
padrão, o gravador mantém o arquivo atual de 50 MiB e um arquivo `.previous`.

Compile a imagem com:

```bash
docker buildx build \
  --load \
  --progress=plain \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus:latest \
  -t gow/cachyos-opengamepadui:latest \
  ./opengamepadui
```

#### Preparação do host

Crie `/etc/udev/rules.d/85-wolf-virtual-inputs.rules`. As duas variantes de
nome do controle Sony são mantidas porque versões diferentes do Wolf usam
`PS5` ou `DualSense`:

```udev
# Permite ao Wolf criar controles virtuais.
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"

# Necessário para emulação de DualSense.
KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"

# Controles virtuais criados pelo Wolf.
KERNEL=="hidraw*", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
KERNEL=="hidraw*", ATTRS{name}=="Wolf DualSense (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf X-Box One (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf DualSense (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf gamepad (virtual) motion sensors", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf Nintendo (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
```

Recarregue as regras e reinicie o container do Wolf:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
docker restart wolf
ls -l /dev/uinput /dev/uhid
```

Na chamada do próprio container `wolf`, estes argumentos são necessários para
suporte completo a controles, incluindo DualSense. Eles são os mesmos usados
pelo exemplo oficial:

```bash
--device /dev/uinput \
--device /dev/uhid \
-v /dev/:/dev/:rw \
-v /run/udev:/run/udev:rw \
--device-cgroup-rule 'c 13:* rmw'
```

Em Compose, o equivalente é:

```yaml
services:
  wolf:
    volumes:
      - /dev/:/dev/:rw
      - /run/udev:/run/udev:rw
    devices:
      - /dev/uinput
      - /dev/uhid
    device_cgroup_rules:
      - 'c 13:* rmw'
```

#### Perfil do aplicativo no Wolf

Use os campos abaixo no perfil OpenGamepadUI. Preserve os mounts de jogos e
launchers que já existirem no seu perfil:

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'OpenGamepadUI (CachyOS)'

    [profiles.apps.runner]
    base_create_json = '''{
  "HostConfig": {
    "IpcMode": "host",
    "Tmpfs": {"/dev/input": "rw,dev,mode=0755"},
    "Privileged": false,
    "SecurityOpt": ["seccomp=unconfined"],
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE", "SYS_ADMIN"],
    "Devices": [
      {
        "PathOnHost": "/dev/ntsync",
        "PathInContainer": "/dev/ntsync",
        "CgroupPermissions": "rwm"
      },
      {
        "PathOnHost": "/dev/uinput",
        "PathInContainer": "/dev/uinput",
        "CgroupPermissions": "rwm"
      },
      {
        "PathOnHost": "/dev/uhid",
        "PathInContainer": "/dev/uhid",
        "CgroupPermissions": "rwm"
      }
    ],
    "DeviceCgroupRules": ["c 10:223 rmw", "c 13:* rmw", "c 244:* rmw"]
  }
}
'''
    devices = [
        '/dev/ntsync:/dev/ntsync:rwm',
        '/dev/uinput:/dev/uinput:rwm',
        '/dev/uhid:/dev/uhid:rwm'
    ]
    env = [
        'GOW_REQUIRED_DEVICES=/dev/uinput /dev/uhid /dev/input/* /dev/dri/* /dev/nvidia*'
    ]
    image = 'gow/cachyos-opengamepadui:latest'
    mounts = []
    name = 'CachyOSOpenGamepadUI'
    ports = []
    type = 'docker'
```

O `tmpfs` privado em `/dev/input` é obrigatório. O `fake-udev` do Wolf cria
nele os nós `event*` e `js*` após o container iniciar, enquanto a regra de
cgroup libera o major 13. A opção `dev` também é obrigatória: sem ela o Docker
monta o `tmpfs` com `nodev`, e o InputPlumber recebe `EACCES` ao abrir o
controle. Não monte `/dev/input` do host nesse perfil, pois isso conflita com a
criação dos mesmos nós pelo `fake-udev`.

Variáveis úteis: `GAMESCOPE_WIDTH`, `GAMESCOPE_HEIGHT`,
`GAMESCOPE_INTERNAL_WIDTH`, `GAMESCOPE_INTERNAL_HEIGHT` e
`OPENGAMEPADUI_STARTUP_FLAGS`. O modo de manutenção `RUN_XFCE=1` continua
disponível porque a imagem herda do Pegasus.

Diretórios do host montados em `~/.config/gamescope` ou
`~/.local/share/opengamepadui` precisam pertencer ao UID/GID `1000:1000`. O
PowerStation fica instalado, mas desligado por padrão porque `/sys` normalmente
é somente leitura no container; use `START_POWERSTATION=1` somente quando o
host fornecer acesso compatível.

Para validar após conectar pelo Moonlight:

```bash
ogui_container="$(
  docker ps --filter ancestor=gow/cachyos-opengamepadui:latest \
    --format '{{.ID}}' | head -n1
)"

docker exec "$ogui_container" \
  test -f /usr/share/inputplumber/devices/59-wolf_virtual_gamepad.yaml
docker exec "$ogui_container" inputplumber devices list
docker exec "$ogui_container" sh -c \
  'for event in /dev/input/event*; do
     name="$(cat "/sys/class/input/${event##*/}/device/name" 2>/dev/null)"
     case "$name" in Wolf\ *) echo "$event: $name";; esac
   done'
docker logs "$ogui_container" 2>&1 |
  grep -E 'inputplumber|Wolf Virtual Gamepad|Started evdev'
```

O resultado esperado é um dispositivo composto `Wolf Virtual Gamepad` no
InputPlumber e pelo menos um `event*` do Wolf. O modo passthrough é proposital:
o OpenGamepadUI lê o controle e o jogo continua recebendo o dispositivo
original.

---

[English README](README.md)
