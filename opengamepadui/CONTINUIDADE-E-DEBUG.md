# OpenGamepadUI no Wolf: continuidade, arquitetura e diagnóstico

Este documento preserva o contexto técnico da imagem OpenGamepadUI deste
repositório. Ele deve ser a primeira leitura antes de alterar input, perfis,
Gamescope, plugins, Wine/Proton ou o processo de build/deploy.

## Snapshot de referência

- Data do snapshot: 2026-08-04.
- Repositório: `mjsf12/WolfImagesCachyos`, branch `main`.
- Commit funcional validado: `c287646d343e0d6c170d8e1e96d7bf9b4de62690`.
- OpenGamepadUI: `0.46.0`.
- InputPlumber: `0.78.0`, pacote local `pkgrel=1.7`.
- PowerStation empacotado: `0.8.1`; desativado por padrão.
- Imagem base: `cachyos/cachyos-v4:latest`.
- Builder do PCK: `ghcr.io/shadowblip/opengamepadui-builder:4.7.1`.
- Commit upstream usado para o PCK:
  `b149644f46b71e175a2ad223e84c18361596691e`.
- Imagem ativa no servidor:
  `gow/cachyos-opengamepadui:latest`, ID observado
  `sha256:2703432af8fa7698377ff9178344a9acebdf7ed38a64f671e11fd9f857ed55f2`.
  O ID é apenas um snapshot e muda a cada build.
- Estado funcional confirmado manualmente: jogos de Lutris, Heroic e Bottles;
  controle em jogos; menus sobre jogos; modo mouse; retorno ao gamepad; saída de
  jogos sem ficar preso em tela preta.

O único comportamento ainda não explicado é um flicker intermitente ao navegar
nos menus do OpenGamepadUI: por menos de um segundo o jogo pode aparecer na
frente e o menu retorna em seguida. Durante o flicker o jogo não recebe input.
Ele foi observado depois da migração do ciclo de overlay para plugin, mas ainda
não há prova de que o plugin seja a causa. Não confundir este sintoma com o
flicker contínuo de launchers causado anteriormente por bibliotecas NVIDIA
incompatíveis.

## Invariantes que não devem ser quebrados

1. O controle source criado pelo Wolf nunca deve chegar diretamente ao jogo.
   Ele é propriedade exclusiva do InputPlumber.
2. Jogos devem enxergar apenas o target virtual
   `Microsoft Xbox Series S|X Controller` criado pelo InputPlumber.
3. Os targets `xbox-series`, `mouse` e `keyboard` devem existir antes de
   Gamescope, Wine e Proton enumerarem `/dev/input`.
4. A rota deve ser aplicada ao objeto D-Bus real de cada CompositeDevice. O
   cache do OpenGamepadUI 0.46 não é uma confirmação suficiente.
5. Uma troca de perfil só é considerada concluída após o `ProfileName` real
   permanecer correto por dois frames.
6. Enquanto um menu do OpenGamepadUI está na frente, o jogo não pode receber
   input, mesmo que ainda exista um estado de jogo abaixo dele na pilha.
7. Bibliotecas NVIDIA versionadas de 64 e 32 bits vêm do volume de driver do
   Wolf. Não instalar `nvidia-utils` nem `lib32-nvidia-utils` nas imagens.
8. O binário, a GDExtension e o PCK do OpenGamepadUI precisam permanecer
   compatíveis. A sessão usa `--skip-update-pack` para impedir que um update
   persistido substitua somente parte desse conjunto.
9. Toda alteração em um plugin empacotado deve aumentar sua versão e atualizar
   o contrato em `tests/test_bundled_plugins.py`; caso contrário uma cópia
   persistida pode continuar sendo usada.
10. Os três patches antigos de overlay são backups históricos e não podem ser
    reaplicados junto com `wolf-gamescope-session`, pois os dois passariam a
    disputar o mesmo estado do Gamescope.

## Arquitetura geral

```text
Moonlight
  -> Wolf cria "Wolf ... (virtual) pad" no container da sessão
  -> InputPlumber toma posse exclusiva do source
  -> CompositeDevice "Wolf Virtual Gamepad"
       -> target xbox-series -> eventN + jsN -> SDL/Wine/Proton -> jogo
       -> target mouse -------\
       -> target keyboard -----+-> bridge libei/EIS -> seat do Gamescope
       -> target D-Bus ------------> InputManager/OpenGamepadUI

OpenGamepadUI
  -> LaunchManager acompanha processos, AppIDs e janelas
  -> wolf-desktop-input decide perfil e InterceptMode
  -> wolf-gamescope-session decide STEAM_OVERLAY e baselayer
  -> Gamescope compõe frontend, jogo e cursor
  -> Wolf captura o frame composto e envia ao Moonlight
```

A imagem segue esta herança:

```text
cachyos/cachyos-v4
  -> gow/cachyos-base
    -> gow/cachyos-pegasus
      -> gow/cachyos-opengamepadui
```

`opengamepadui` herda launchers, Wine/Proton, emuladores, caches e o modo XFCE
do Pegasus. O modo normal inicia a sessão oficial `gamescope-session-plus`; com
`RUN_XFCE=1`, o startup delega novamente ao Pegasus para manutenção.

## Inicialização da sessão

1. O entrypoint da base cria o usuário dinâmico da sessão e configura grupos
   de dispositivos.
2. `/etc/cont-init.d/50-opengamepadui-services`:
   - adiciona o usuário ao grupo `inputplumber`, necessário para mutações D-Bus
     autorizadas pelo polkit;
   - cria `/dev/input` antes do watcher evdev do InputPlumber;
   - inicia InputPlumber;
   - materializa manualmente `eventN` para gamepad, mouse e teclado e `jsN` para
     o target Xbox, porque o `/dev/input` privado do Wolf não tem udev;
   - registra metadados sintéticos de udev para o target Xbox;
   - inicia o bridge InputPlumber -> Gamescope EIS;
   - inicia o gravador contínuo durante a vida do container;
   - mantém o atalho Guide genérico e corrige composites que nasceram em
     `InterceptMode=0`.
3. `/opt/gow/startup.sh`:
   - valida diretórios persistentes;
   - copia os cinco ZIPs de plugins para o diretório do usuário;
   - grava as variáveis de input em cada bottle existente;
   - prepara dimensões e ambiente da sessão;
   - executa `dbus-run-session -- gamescope-session-plus opengamepadui`.
4. A configuração da sessão em `session/opengamepadui` executa diretamente
   `/usr/share/opengamepadui/opengamepad-ui.x86_64 --skip-update-pack`.
   Isso evita o wrapper abrir um segundo Gamescope por interpretar
   `/run/user/wolf` de maneira incorreta.
5. O hook `post_gamescope_start` chama `gamescopectl cursor_composite 2` para o
   cursor fazer parte do frame transmitido.

## InputPlumber e a rota autoritativa

O arquivo `pkgbuilds/inputplumber-wolf/59-wolf_virtual_gamepad.yaml` reconhece
sources `Wolf *` com `ID_INPUT_JOYSTICK=1`, limita cada composite a um source e
cria permanentemente estes targets:

- `xbox-series`;
- `mouse`;
- `keyboard`.

Manter os três targets vivos evita hotplug tardio durante uma troca de perfil.
No perfil normal o target Xbox recebe eventos. No perfil desktop, mouse e
teclado recebem os mapeamentos enquanto a interceptação `GamepadOnly` impede
que controles não mapeados vazem para o Xbox.

O patch local do InputPlumber faz duas coisas essenciais:

- inclui controles virtuais Wolf na whitelist de dispositivos virtuais
  gerenciáveis;
- mantém acordes de ativação com múltiplos botões funcionando nos modos
  `Always` e `GamepadOnly`, inclusive segurando o Guide sintético até o primeiro
  botão físico ser solto. Isso permite Guide+A e Guide+X.

### InterceptMode

| Valor | Nome no código | Uso esperado |
| --- | --- | --- |
| `1` | `Pass` | Jogo está rodando e é o estado em primeiro plano; eventos vão ao target do jogo. |
| `2` | `Always` | Frontend ou popup está em primeiro plano; OpenGamepadUI recebe o controle e o jogo fica bloqueado. |
| `3` | `GamepadOnly` | Jogo está em primeiro plano com modo desktop; gamepad fica interceptado, mas mouse/teclado virtuais passam. |

Um jogo apenas existir na pilha não basta para selecionar `Pass`: o estado
atual também precisa ser `in_game` e nenhum popup pode estar aberto. Esta regra
corrigiu o bug em que o usuário navegava no menu e no jogo ao mesmo tempo.

Ao abrir um menu durante o modo mouse, a rota muda deliberadamente para
`Always`. Nesse momento o controle navega no OpenGamepadUI, não no launcher que
está embaixo. Portanto não é um fluxo válido tentar usar o mouse virtual no
launcher enquanto o menu do OpenGamepadUI está aberto.

## Plugin `wolf-desktop-input`

Versão no snapshot: `1.0.19`.

Responsabilidades:

- configurar Guide físico ou `Start + Select` como Guide genérico;
- instalar o perfil `Wolf Desktop Mouse` no diretório do usuário;
- alternar desktop/gamepad;
- escolher o InterceptMode conforme jogo, estado em primeiro plano, popup e
  intenção de desktop;
- registrar controles na barra rápida;
- restaurar o perfil específico do jogo ou o perfil global;
- registrar traces estruturados de cada transição.

Atalhos:

- `Start + Select`: Guide genérico; ao soltar, abre o menu principal;
- `Start + Select + A`: barra rápida;
- `Start + Select + X`: alterna desktop mouse/gamepad;
- em controles cujo Guide funciona, os equivalentes são Guide, Guide+A e
  Guide+X.

Perfil desktop:

- analógico direito: movimento do mouse;
- `A` ou RT: clique esquerdo;
- `B` ou LT: clique direito;
- RB/LB: scroll para cima/baixo;
- D-pad: setas do teclado;
- analógico esquerdo, North e cliques dos analógicos são bloqueados;
- Guide, QuickAccess e ação de alternância continuam expostos via D-Bus.

Velocidade padrão: 800 pixels por segundo; configurável entre 300 e 1600.
`Automatic for desktop launchers` é `false` por padrão. Quando ativado, o modo
desktop entra automaticamente para itens sem argumentos cujo comando é
`bottles`, `heroic` ou `lutris`, ou para itens com metadata
`desktop_input=true`.

### Transações de perfil

`ProfileTransition` implementa `latest request wins` com um contador de
geração. Trabalho deferred antigo não pode confirmar uma intenção mais nova.
Cada transição:

1. registra a intenção;
2. aplica imediatamente uma rota de guarda;
3. carrega o perfil no LaunchManager e em todos os composites vivos;
4. relê `ProfileName` por D-Bus;
5. exige dois frames estáveis;
6. tenta no máximo quatro vezes;
7. confirma a intenção ou retorna ao último modo comprovado.

Popups suspendem a confirmação do perfil desktop, pois o InputManager instala
temporariamente seu perfil de navegação. Ao fechar o popup, a intenção mais
recente é reconciliada. Ao iniciar um jogo real, desktop mode é sempre
restaurado para gamepad antes de entregar input ao jogo.

## Mouse, EIS e cursor

São dois problemas independentes:

1. Movimento/clique: `inputplumber-gamescope-bridge` lê os targets evdev mouse
   e teclado e os injeta no seat EIS do Gamescope, normalmente pelo socket
   `gamescope-0-ei`. O bridge espera tanto os targets quanto o socket existirem.
2. Visibilidade: em backend nested, Gamescope pode entregar o cursor ao
   compositor externo em vez de desenhá-lo no framebuffer. Como o Wolf
   transmite o frame, o cursor ficava clicável porém invisível. O hook
   `gamescopectl cursor_composite 2` força sua composição no vídeo.

Se o ponteiro não move, investigar target mouse e bridge EIS. Se move/clica no
host ou por posição, mas não aparece no Moonlight, investigar composição do
cursor. Não misturar os dois diagnósticos.

## Wine, Proton e o controle duplicado

Winebus/Proton inicialmente enumerava o source Wolf e o target InputPlumber. O
source estava tomado pelo InputPlumber e virava um XInput sem eventos, enquanto
o jogo podia selecionar o dispositivo errado. A solução atual usa:

```text
PROTON_USE_SDL=1
PROTON_PREFER_SDL=1
PROTON_DISABLE_HIDRAW=1
SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x045E/0x0B12
```

O VID/PID corresponde ao target `xbox-series`. Essas variáveis estão no ENV da
imagem e são aplicadas explicitamente a cada bottle por
`configure_bottles_input.py`, porque Bottles filtra variáveis herdadas. Lutris
e Heroic devem preservar o mesmo ambiente para suas execuções Wine/Proton.

Sintoma típico de regressão: OpenGamepadUI mostra modo desktop ou troca de
perfil, mas o jogo continua vendo um controle normal independente. Isso quase
sempre significa que o source Wolf voltou a vazar ou que o jogo escolheu uma
rota HID/evdev que não passa pelo target InputPlumber.

## Gamescope e plugin `wolf-gamescope-session`

Versão no snapshot: `1.0.0`.

O plugin substitui três patches antigos de overlay usando APIs públicas do
OpenGamepadUI 0.46. Se `LaunchManager.should_manage_overlay` já estiver falso,
ele não assume propriedade. Caso contrário:

1. salva o valor original;
2. define `should_manage_overlay=false` para desativar o callback nativo, que
   escrevia `STEAM_OVERLAY=1` tanto na entrada quanto na saída;
3. observa `in_game_state.state_entered`, `state_exited` e
   `LaunchManager.all_apps_stopped`;
4. descobre a janela OGUI pelo PID no XWayland OGUI;
5. aplica a decisão ao Gamescope;
6. devolve a propriedade ao LaunchManager no unload.

Política:

| Evento/estado | `STEAM_OVERLAY` | Baselayer |
| --- | --- | --- |
| Entrada em jogo | `1` | preservado |
| Menu/popup empilhado sobre jogo | `1` | preservado |
| Saída real do estado de jogo | `0` | preservado |
| Último app parou | `0` | remove janela antiga e restaura `[EXTRA_UNKNOWN_GAME_ID, OVERLAY_GAME_ID]` |

O plugin também usa geração `latest request wins`. O callback final
`all_apps_stopped` deve invalidar um `state_exited` enfileirado instantes antes;
uma nova entrada em jogo deve invalidar um cleanup ainda pendente. A descoberta
da janela tenta por até dez frames, mas a aplicação é síncrona quando a janela
já é conhecida.

### Flicker intermitente atual

O fluxo mudou de código interno do LaunchManager para sinais públicos de
estado. Embora a decisão seja equivalente, agora existem estes limites de
sincronização:

- a máquina de estados altera a janela/estado em primeiro plano;
- o sinal chama o plugin;
- o plugin escreve o átomo de overlay;
- Gamescope aplica composição e foco no seu próximo ciclo.

Uma janela de um frame entre esses passos é uma hipótese plausível para o jogo
aparecer brevemente. Também pode ser uma troca normal de foco/AppID do
Gamescope não causada pelo átomo de overlay. Como o jogo não recebeu input e o
menu se recuperou sozinho, não há evidência de erro na política de input.

Na próxima ocorrência, não reiniciar nem fechar imediatamente. Anotar:

- se foi menu principal, barra rápida, Home, configurações ou retorno ao jogo;
- se aconteceu ao abrir, fechar ou trocar página;
- nome do jogo/launcher;
- horário aproximado;
- se houve uma ou várias piscadas.

Capturar no container da sessão:

```bash
docker ps --format '{{.ID}} {{.Image}} {{.Names}}'
CONTAINER_ID=abc123
docker logs --since 3m "$CONTAINER_ID" 2>&1 | \
  grep -E 'WolfGamescopeSession|WolfDesktopInput|LaunchManager|Overlay reconciled|all_apps_stopped'
docker exec "$CONTAINER_ID" sh -lc \
  'for display in :0 :1; do DISPLAY=$display xprop -root 2>/dev/null | grep -E "GAMESCOPE|STEAM"; done'
```

Se os logs atuais não forem suficientes, a próxima instrumentação deve
registrar, no mesmo evento: geração, motivo, pilha global, popup atual, ID da
janela OGUI, `STEAM_OVERLAY`, baselayer apps e focusable apps/windows antes e
depois da escrita. Não alterar a política antes de obter essa captura.

## Patches do OpenGamepadUI

### Ainda aplicados no PCK

- `opengamepadui-godot-4.7-maximum-size.patch`: renomeia uma propriedade que
  conflita com Godot 4.7 em diálogos de instalação.
- `opengamepadui-gamescope-appid-window-detection.patch`: interpreta
  `GAMESCOPE_FOCUSABLE_WINDOWS` como triplas `[window_id, app_id, pid]` e usa
  AppID como fallback quando um launcher filho perde `OGUI_ID`.
- `opengamepadui-launcher-exit-cleanup.patch`: finaliza corretamente apps cuja
  janela desapareceu e evita estado de jogo preso. Usa 3 s para stop explícito
  e 8 s para janela espontaneamente ausente.

Esses três mexem em internals sem API pública equivalente e continuam patches.

### Aposentados e preservados

- `opengamepadui-overlay-return.patch`;
- `opengamepadui-overlay-menu.patch`;
- `opengamepadui-final-overlay-cleanup.patch`.

Os originais permanecem em `patches/` e cópias byte a byte ficam em
`patches-backup/overlay/`. O Dockerfile compara os dois conjuntos com `cmp` e
não aplica esses patches. O comportamento pertence ao plugin
`wolf-gamescope-session`.

## Plugins empacotados

Todos são exportados em ZIPs independentes e copiados para
`/usr/share/opengamepadui/plugins`:

| ID | Versão | Origem |
| --- | --- | --- |
| `wolf-desktop-input` | `1.0.19` | Este repositório |
| `wolf-gamescope-session` | `1.0.0` | Este repositório |
| `lutris` | `2.0.1` | `../OpenGamepadUI-lutris`, commit `601bd6b2f3c035cfdce7f0bb0c4d14bf55992e87` |
| `heroic` | `0.1.1` | `../OpenGamepadUI-heroic`, working tree local importada em 2026-08-04 |
| `bottles` | `0.1.2` | `../OpenGamepadUI-bottles`, working tree local importada em 2026-08-04 |

As fontes vendorizadas estão em `plugins/`. O PNG do Heroic é armazenado como
base64 para permanecer lossless no repositório, decodificado no build e
verificado pelo SHA-256
`a57601ee8357f0b51d987a03eddeef7bab4a777955b9fe86b9f8d6a7891aa654`.

Em toda inicialização, `install-opengamepadui-plugins.sh` sobrescreve os cinco
arquivos no diretório persistente
`~/.local/share/opengamepadui/plugins`. Aumento de versão garante que o loader
extraia a revisão nova sobre uma cópia persistida antiga.

## NVIDIA e o flicker antigo dos launchers

O Wolf monta as bibliotecas compatíveis com o driver do host em:

```text
/usr/nvidia/lib
/usr/nvidia/lib32
```

`/etc/ld.so.conf.d/00-nvidia.conf` dá prioridade a esses diretórios. A base
instala somente `libglvnd`, loaders Vulkan de 64/32 bits e camadas Mesa. Pegasus
instala `vulkan-swrast`/`lib32-vulkan-swrast` como providers seguros e falha o
build se `nvidia-utils` ou `lib32-nvidia-utils` aparecerem.

O problema anterior de launcher de jogo piscando continuamente e erros Vulkan
veio de userspace NVIDIA versionado dentro da imagem não corresponder ao driver
volume. Não tentar resolver reinstalando driver NVIDIA no container. Quando o
sintoma é um único frame do jogo durante navegação do OpenGamepadUI, a causa é
provavelmente outra e deve ser investigada no fluxo Gamescope/overlay.

## Diagnóstico contínuo durante a sessão

Por padrão, `inputplumber_diagnostics.py` grava:

```text
/home/gow/.local/state/opengamepadui/wolf-input-trace.jsonl
```

Ele registra:

- attach/detach de source e targets evdev;
- eventos relevantes de botões, eixos, mouse e target Xbox;
- lista de CompositeDevices;
- mudanças de `InterceptMode`, `ProfileName`, `TargetDevices` e sources;
- sinais D-Bus de input e propriedades;
- conteúdo e SHA-256 do perfil desktop;
- posição do ponteiro X11;
- heartbeat a cada dez segundos.

O arquivo gira em 50 MiB para `.previous`. `WOLF_INPUT_DIAGNOSTICS=0` desativa
o gravador; `WOLF_INPUT_TRACE_MAX_BYTES` altera o limite.

Importante: `.local/state` não está montado no host na configuração atual. A
captura desaparece quando o container da sessão é removido. Copiar ou ler o
arquivo antes de encerrar a sessão:

```bash
CONTAINER_ID=abc123
docker exec "$CONTAINER_ID" tail -n 300 \
  /home/gow/.local/state/opengamepadui/wolf-input-trace.jsonl
docker cp \
  "$CONTAINER_ID":/home/gow/.local/state/opengamepadui/wolf-input-trace.jsonl \
  /tmp/wolf-input-trace.jsonl
```

O plugin também escreve eventos `[trace]` nos logs do container, com sequência,
ticks, intenção/aplicação do desktop, geração, estado de jogo, popup, devices,
perfil e rota.

### Comandos de inspeção de input

```bash
CONTAINER_ID=abc123
docker exec "$CONTAINER_ID" busctl --system --list tree org.shadowblip.InputPlumber
docker exec "$CONTAINER_ID" busctl --system get-property \
  org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice \
  InterceptMode ProfileName TargetDevices SourceDevicePaths
docker exec "$CONTAINER_ID" sh -lc \
  'for p in /sys/class/input/event*; do printf "%s " "$p"; cat "$p/device/name"; done'
docker exec "$CONTAINER_ID" ls -l /dev/input
```

## Mapa rápido de sintomas

| Sintoma | Primeira suspeita | Evidência a procurar |
| --- | --- | --- |
| Menu e jogo respondem juntos | `InterceptMode=1` com menu na frente | `[trace] intercept_sync_*`, estado global e popup |
| Só o menu responde e o jogo não | modo preso em `2`, perfil não restaurado ou target Xbox ausente | `ProfileName`, `InterceptMode`, `eventN/jsN` |
| Jogo vê controle, mas perfis não alteram nada | source Wolf vazou direto | lista evdev, SDL/HID, VID/PID visível ao processo |
| Modo mouse confirma, mas ponteiro não move | target mouse ou bridge EIS | eventos `target_mouse`, log `connected to Gamescope EIS input seat` |
| Ponteiro clica, mas está invisível no Moonlight | cursor não composto | mensagem `Gamescope cursor composition enabled` |
| Desktop não volta a gamepad | corrida de perfil ou falha D-Bus | geração, retries, `ProfileName`, polkit/grupo `inputplumber` |
| Tela preta após fechar jogo | overlay/baselayer ou app preso | `all_apps_stopped`, log do plugin, baselayer, RunningApp |
| Jogo não aparece após launcher | associação de janela perdeu `OGUI_ID` | focusable windows/AppID e logs do RunningApp |
| Launcher pisca continuamente/Vulkan falha | libs NVIDIA incompatíveis | `pacman -Q nvidia-utils lib32-nvidia-utils`, paths do driver volume |
| OGUI cai ao iniciar depois de alterar plugin | erro de parse/load GDScript | `SCRIPT ERROR`, `Failed to load script`, ausência de `Initialized plugin` |
| Um único frame do jogo aparece sob menu | sincronização foco/overlay ainda não comprovada | captura conjunta de estados e átomos Gamescope |

## Logs ruidosos que nem sempre são falhas

Estes avisos já apareceram com a sessão funcional:

- `/dev/fuse` ausente no document portal;
- PipeWire indisponível para captura do próprio Gamescope;
- NetworkManager/Bluetooth não executando;
- HardwareManager não identificando GPU NVIDIA para controles de performance;
- warnings de `xkbcomp`;
- alguns formatos Vulkan sem DRM modifiers.

Eles só devem virar prioridade se coincidirem com uma função que realmente usa
o subsistema. Em contraste, são sinais relevantes:

- `Profile transition failed`;
- `InputPlumber did not confirm`;
- ausência do target `jsN`;
- bridge EIS sem conexão;
- `Unable to set STEAM_OVERLAY`;
- `SCRIPT ERROR`/plugin não inicializado;
- OpenGamepadUI ou Gamescope encerrando repetidamente.

## Testes e contratos do build

No snapshot funcional passaram 60 testes de lógica:

- 8 do core PCK corrigido: AppID/focusable windows e cleanup de launcher;
- 36 do `wolf-desktop-input`;
- 11 do `wolf-gamescope-session`;
- 3 do plugin Bottles;
- 2 do helper Heroic.

Além disso o build executa:

- self-test do bridge EIS;
- self-test do configurador Bottles;
- self-test do gerador de metadata udev;
- testes do gravador de diagnóstico;
- verificação de autorização polkit idempotente;
- simulador do acorde Guide genérico;
- verificação dos cinco ZIPs isolados, sem arquivos de outro plugin ou fontes
  de teste;
- teste do instalador de plugins com comparação byte a byte;
- smoke test do binário release carregando o PCK e todos os plugins;
- verificação de ausência de `SCRIPT ERROR`, scripts ausentes e objetos nulos;
- restauração e verificação de `cap_sys_nice=eip` no binário.

O smoke headless aceita exit `139` somente após comprovar que todos os plugins
foram inicializados. Esse encerramento pode ocorrer ao forçar `--quit-after` em
threads que normalmente vivem pela sessão inteira; não é aceito como substituto
das verificações de carregamento.

### Matriz manual mínima depois de qualquer mudança

1. Iniciar OpenGamepadUI e confirmar os cinco plugins nos logs.
2. Abrir um jogo e confirmar controle.
3. Abrir menu principal sobre o jogo; jogo deve ficar visível por baixo, sem
   receber input.
4. Abrir barra rápida e navegar.
5. Fechar menus e confirmar retorno do controle ao jogo.
6. Ativar modo mouse, mover, clicar e rolar em launcher.
7. Voltar a gamepad e confirmar jogo novamente.
8. Fechar o jogo pelo menu e confirmar retorno sem tela preta.
9. Abrir um segundo jogo para verificar cleanup da sessão anterior.
10. Repetir ao menos uma vez por Lutris, Heroic e Bottles quando a mudança tocar
    lançamento, janela, Wine/Proton ou input.

## Build e deploy

Build apenas do OpenGamepadUI usando a base Pegasus atual:

```bash
docker build --progress=plain \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus:latest \
  -t gow/cachyos-opengamepadui:latest \
  opengamepadui
```

Quando dependências/base mudarem, respeitar a ordem:

```bash
docker build -t gow/cachyos-base:latest base
docker build \
  --build-arg BASE_IMAGE=gow/cachyos-base:latest \
  -t gow/cachyos-pegasus:latest pegasus
docker build \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus:latest \
  -t gow/cachyos-opengamepadui:latest opengamepadui
```

O Dockerfile usa `paru` atualmente. Pacotes de repositório são instalados com
`paru --repo`; OpenGamepadUI, InputPlumber modificado e PowerStation usam
PKGBUILDs locais via `paru -Bi`. Portanto qualquer descrição antiga dizendo
que a imagem não usa `paru` está incorreta para este snapshot.

### Servidor

- SSH: `wolf@192.168.69.112` com chave.
- Repositório: `/home/wolf/WolfImagesCachyos`.
- Compose do Wolf: `/opt/stacks/wolf/compose.yaml`.
- Config Wolf: `/etc/wolf/cfg/config.toml`.
- O Git do repositório pertence a `wolf`; executar Git como `root` gera
  `dubious ownership`. Usar `wolf` para pull/status e `root` para Docker.
- Existe um arquivo não rastreado `q` no repositório do servidor; ele não faz
  parte deste trabalho e deve ser preservado.

Fluxo de deploy:

```bash
ssh wolf@192.168.69.112 \
  'cd /home/wolf/WolfImagesCachyos && git pull --ff-only'
ssh root@192.168.69.112 \
  'cd /home/wolf/WolfImagesCachyos && docker build --progress=plain --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus:latest -t gow/cachyos-opengamepadui:latest opengamepadui'
ssh root@192.168.69.112 \
  'docker compose -f /opt/stacks/wolf/compose.yaml restart wolf'
ssh root@192.168.69.112 \
  'docker compose -f /opt/stacks/wolf/compose.yaml ps && docker logs --since 2m wolf'
```

Não há necessidade de reiniciar um container de app antigo se nenhuma sessão
estiver ativa. O Wolf usa a imagem nova na próxima abertura do OpenGamepadUI.

### Configuração Wolf necessária

O perfil funcional usa:

- `start_virtual_compositor=true`;
- imagem `gow/cachyos-opengamepadui:latest`;
- `Tmpfs` em `/dev/input`;
- `seccomp=unconfined`;
- capabilities `NET_RAW`, `MKNOD`, `NET_ADMIN`, `SYS_NICE`, `SYS_ADMIN`;
- devices `/dev/ntsync`, `/dev/uinput`, `/dev/uhid`;
- regras cgroup `c 10:223 rmw`, `c 13:* rmw`, `c 244:* rmw`;
- `START_INPUTPLUMBER=1`, `START_POWERSTATION=0`;
- resolução externa/interna 1920x1080 no snapshot.

Montagens persistentes especialmente relevantes:

```text
/home/wolf/opengamepadui_share -> /home/gow/.local/share/opengamepadui
/home/wolf/gamescope_config -> /home/gow/.config/gamescope
/home/wolf/gamescope_session_config -> /home/gow/.config/gamescope-session-plus
```

Também são montadas configurações e dados de Lutris, Heroic, Bottles, Steam,
UMU, jogos e emuladores. Não apagar ou substituir esses diretórios durante
debug de imagem.

## Atualização futura do OpenGamepadUI/InputPlumber

Ao atualizar OpenGamepadUI:

1. atualizar `pkgver` e SHA-256 em
   `pkgbuilds/opengamepadui-bin/PKGBUILD`;
2. selecionar o commit fonte exatamente correspondente e atualizar
   `OPENGAMEPADUI_COMMIT`/`OPENGAMEPADUI_SOURCE_SHA256`;
3. confirmar versão do builder Godot usada pelo release;
4. tentar reaplicar somente os três patches ativos e revisar cada hunk;
5. revisar APIs públicas usadas pelos dois plugins;
6. não reativar automaticamente os patches aposentados de overlay;
7. executar build completo e smoke do binário real;
8. repetir toda a matriz manual.

Ao atualizar InputPlumber:

1. revisar whitelist de dispositivos virtuais e semântica dos InterceptModes;
2. revisar o patch do acorde multi-botão;
3. conferir nomes D-Bus, target `xbox-series` e formato dos perfis;
4. confirmar criação de `eventN` e `jsN` no `/dev/input` privado;
5. rodar simulador do acorde e testes de diagnóstico;
6. testar source -> composite -> target ponta a ponta em Wine/Proton.

## Histórico de commits úteis

- `485c557`: primeira imagem OpenGamepadUI/Gamescope.
- `83a78c1`: associação de janelas de jogos filhos por AppID.
- `647a14f`: retorno do menu depois de fechar jogo.
- `0492734`: primeiro modo desktop pelo controle.
- `05b40a8`: rota autoritativa via InputPlumber e bridge EIS.
- `d91c299`: expõe somente o controle target do InputPlumber.
- `12ef8db`: restauração autoritativa de perfil e configuração Bottles.
- `4af76c2`: cursor composto no stream.
- `8171875`: serialização latest-wins das transições de perfil.
- `5113e40`: menu/frontend bloqueia o jogo quando está em primeiro plano.
- `c287646`: plugin de sessão, backups dos patches e plugins vendorizados.
- `c1c72c4`: providers seguros no Pegasus e proibição de userspace NVIDIA
  versionado dentro da imagem.

Para entender uma regressão, comparar primeiro com esses commits em vez de
reintroduzir soluções intermediárias que já foram substituídas.

## Fontes locais históricas

Foram usadas durante a investigação inicial:

```text
/home/mjsf12/Downloads/OpenGamepadUI-main/
/home/mjsf12/Downloads/gamescope-session-opengamepadui-main (1)/gamescope-session-opengamepadui-main/
../OpenGamepadUI-lutris/
../OpenGamepadUI-heroic/
../OpenGamepadUI-bottles/
```

O código versionado neste repositório é a fonte de verdade para build. As
pastas Downloads são apenas referência upstream; os três plugins irmãos são
árvores de desenvolvimento, enquanto as cópias em `opengamepadui/plugins` são
as revisões efetivamente empacotadas.
