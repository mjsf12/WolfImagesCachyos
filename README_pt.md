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

### Localidade/Teclado
- Defina `LANG`, `LANGUAGE`, `LC_ALL` para locale
- Defina `XKB_*` para layout de teclado (exemplo: ABNT2 brasileiro)

## Build de Imagens

O build segue uma estrutura hierárquica:

```
base (NewImages/base)
   └── app (NewImages/heroic, NewImages/firefox, etc.)
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

### Build de Todos os NewImages

```bash
# Base
docker build -t gow/cachyos-base NewImages/base

# Apps
docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
docker build -t gow/cachyos-firefox --build-arg BASE_IMAGE=gow/cachyos-base NewImages/firefox
```

## Fluxo Completo

```bash
# 1. Build da base
docker build -t gow/cachyos-base NewImages/base

# 2. Build do seu app
docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic

# 3. Use no config.toml do Wolf
[[profiles.apps]]
    title = 'Heroic (CachyOS)'
    [profiles.apps.runner]
    image = 'gow/cachyos-heroic'
    type = 'docker'
    ...
```

---

[English README](README.md)