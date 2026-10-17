# MacStrike — Handoff (atualizado 2026-10-17, ~00:30)

Contexto para a próxima sessão. Lucas Olegario (pt-BR), `/Users/lucasolegario/rea`.

## Como retomar esta sessão

```sh
cd /Users/lucasolegario/rea
claude --continue     # retoma a sessão mais recente deste diretório
# ou:  claude --resume   (escolher da lista)
```

Transcrição completa (41 MB):
`/Users/lucasolegario/.claude/projects/-Users-lucasolegario-rea/ed33136a-d153-4c31-bceb-078ed8f1e0a1.jsonl`

**Pendência imediata:** o usuário vai reiniciar o iTerm para conceder permissão de
**Screen Recording**. Com ela, `screencapture` passa a funcionar e o agente pode
**ver** a janela da Steam em vez de depender de descrição. Usar:
`screencapture -x -R<x>,<y>,<w>,<h> out.png` e ler o PNG.

---

## O PROBLEMA ATUAL: janela da Steam preta

### O que está PROVADO (não repetir essas investigações)

A Steam roda **saudável** sob Wine aberto (Gcenx 11.18) no bottle
`Bottles/CS2-gcenx-clean`:

- `steam.exe` ×2, `steamwebhelper` ×5 (browser, gpu-process, utility, renderer),
  `steamservice`, `explorer.exe` — todos vivos
- Rede OK: `Connectivity test: result=Connected`, IPv6 HTTP/UDP SUCCESS,
  `ConnectionCompleted()` em `cmp2-atl3.steamserver.net:443`
- **Zero** asserts, **zero** `c0000005`, **zero** falhas de `h264_decoder_create`
  no log atual (2202 linhas)
- **A JANELA EXISTE**, com título e tamanho corretos:
  `'Iniciar a sessão no Steam' pos=(416,297) tam=700×440`
  (obtido via `osascript` enumerando janelas do processo `wine`)

**Conclusão: é puramente problema de PINTURA/COMPOSITING.** Não é processo, não é
rede, não é crash, não é codec. O conteúdo não chega aos pixels.

### PRÓXIMA HIPÓTESE (a mais promissora, não testada)

Os fixmes do log atual apontam para DPI/Retina:

```
fixme:win:create_window_handle DPI context 0x22 not implemented   (×24)
fixme:dwmapi:DwmSetWindowAttribute stub
fixme:dwmapi:DwmExtendFrameIntoClientArea stub
```

Num Mac Retina (M5), contexto de DPI não implementado é causa clássica de janela
criada mas não pintada. **Testar:**

1. `HKCU\Software\Wine\Mac Driver` → `RetinaMode` = `y` (e também `n`)
2. Forçar DPI: `HKCU\Software\Wine\Fonts` → `LogPixels`
3. Flags do Chromium ainda não testadas: `--disable-direct-composition`,
   `--force-device-scale-factor=1`, `-cef-single-process`
4. Comparar com o `winemac.so` do CrossOver, que é **8,2% maior**
   (467.456 vs 432.224 bytes) — eles têm patches de display que o aberto não tem

### Pistas JÁ DESCARTADAS (não gastar tempo)

| Hipótese | Veredito |
|---|---|
| Flags `-cef-disable-gpu` etc. | Já aplicadas pelo código; não resolvem |
| Virtual desktop do Wine | Testado 2026-10-16, continuou preto |
| `-vgui` (UI clássica) | Steam moderna **ignora**; webhelper continua subindo |
| `SIO_ADDRESS_LIST_SORT failed 10045` | **BENIGNO** — ocorre também no CrossOver, onde funciona |
| `WSALookupServiceBegin failed: 8` | Benigno (Chromium só não monitora mudança de rede) |
| `ws2_32` do CrossOver ser diferente | Praticamente idêntico (45008 vs 44864 bytes, 0,3%) |
| Prefix contaminado por 2 Wines | Real, mas **não** era a causa da tela preta |
| GPTK (Gcenx/game-porting-toolkit) | Release "3.0-3" embala **Wine 7.7 de 2022**; Steam crasha com page fault |

---

## RESOLVIDO HOJE: crash do H.264 (causa raiz real, corrigida)

Diagnosticado com `WINEDEBUG=+seh`:

```
fixme:mfplat:MFPluginControl_GetPreferredClsidByIndex
code=c0000005                                           ← access violation
err:winediag:h264_decoder_create GStreamer doesn't support H.264 decoding
```

O CEF da Steam pedia decoder H.264 via `mfplat` → `winegstreamer` sem backend →
access violation → webhelper morria.

**Correção:** GStreamer **1.28.8** instalado em `/Library/Frameworks/GStreamer.framework`
(pacote oficial, 149 MB, instalado via diálogo nativo do macOS). Provê
`avdec_h264`, `openh264dec` e `vtdec`/`vtdec_hw` (VideoToolbox).

Confirmado pela análise do CrossOver: **eles empacotam o GStreamer** e decodificam
via `applemedia` (VideoToolbox, hardware). Isso importa pro problema de calor:
decode por software queima CPU.

---

## Análise do CrossOver com `rea` (interoperabilidade; nada copiado)

`rea` 6.5.0 em `~/.npm/_npx/9b9809298fe40d2c/node_modules/rea-agents`, binário
global `rea`. Comandos úteis: `inspect-binary-layout`, `inspect-macho`,
`decompile`, `function`, `compare`.

Achados (CrossOver 26.3.0 em `~/Applications/CrossOver.app`):

1. **Empacota GStreamer** (`lib64/libgst*.dylib` + `winegstreamer.so`) — confirma
   o diagnóstico do H.264
2. **18 plugins curados** (vs 257 do pacote oficial); H.264 vem de
   `libgstapplemedia.dylib` = **VideoToolbox (hardware)** + `videoparsersbad`
   para parsing. **Não** usam libav nem openh264
3. **`crossover.inf`** usa `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` —
   valida de forma independente o mecanismo do nosso `DllOverridePolicy`
4. Módulos que o Wine aberto **não** tem: `bcrypt.so` (nativo; no aberto é stub,
   254 `fixme:bcrypt:BCryptGenRandom` no log), `cxcompatdb.so` (banco de ajustes
   por app), `winebth.so`, `winelib.so`, `wpcap.so`
5. `winemac.so` **8,2% maior** → patches de display

---

## Estado do código (branch `gui-aurora-redesign`, PR #1)

https://github.com/lucasolegario/mac-strike/pull/1 — **145 checks passando**
(`swift build && swift run selftest`)

Commits de hoje, além da GUI Aurora (12 tarefas):
- `62dc333` strings do engine/runner em inglês
- `a3482b8` overlay de progresso ao lançar jogo (`LaunchMonitor`, `LaunchOverlay`,
  `ProcessDetection`, `Game.processName`)
- `ab81d50` **`DllOverridePolicy`** (override por app) + **`GStreamerDependency`**
- `7131009` ranking de decoders H.264, VideoToolbox primeiro

**Convenção de idioma:** código, comentários, commits e PRs em **en-US**; copy de
UI em **pt-BR**. (Memória salva em
`~/.claude/projects/-Users-lucasolegario-rea/memory/`.)

**Zero referências a CrossOver no repo** — verificado por grep. O suporte que eu
havia escrito (flavor `.crossover`, `CrossOverLocator`) foi **revertido** a pedido
do usuário: o MacStrike deve ter a própria solução.

### Dois bugs de engine corrigidos hoje

1. **`DllOverridePolicy`** — `WINEDLLOVERRIDES` era aplicado ao prefix inteiro, então
   as DLLs de tradução gráfica eram impostas ao cliente Steam. Medido: com override
   global a Steam morria em ~5s; sem ele, completava a auto-atualização de 241 MB.
   Agora registra por executável via `AppDefaults`. Default `.perApplication`.
2. **`GStreamerDependency`** — detecta framework **e** decoder real, ranqueia
   VideoToolbox (hardware) na frente dos de software, monta a URL oficial (só
   versões estáveis — minor par) e instala pelo diálogo nativo do macOS.

---

## Bottles na máquina

| Caminho | Conteúdo |
|---|---|
| `Bottles/CS2` | **69 GB de CS2** — original, criado pelo Wine do CrossOver. Intacto. Funciona pelo comando manual abaixo |
| `Bottles/CS2-gcenx-clean` | Laboratório: prefix nascido do Wine aberto, Steam instalada e atualizada. É onde o teste da tela preta roda |

**Comando manual que FUNCIONA (CrossOver, muleta local, NUNCA no repo):**

```sh
CX="$HOME/Applications/CrossOver.app/Contents/SharedSupport/CrossOver"
PREFIX="$HOME/Library/Application Support/MacStrike/Bottles/CS2"
env WINEPREFIX="$PREFIX" CX_ROOT="$CX" WINELOADER="$CX/bin/wineloader" \
  WINESERVER="$CX/bin/wineserver" WINEDLLPATH="$CX/lib64/wine:$CX/lib/wine" \
  WINEMSYNC=1 WINEDEBUG=-all \
  "$CX/bin/wineloader" "C:\\Program Files (x86)\\Steam\\steam.exe" \
  -cef-disable-gpu -cef-disable-gpu-compositing -no-cef-sandbox
```

Histórico (índice 212 da transcrição): foi **trocar o binário do Wine** que
resolveu a tela preta em 2026-10-16 — **não** houve código de renderização. As
flags do CEF, o virtual desktop e remover os overrides do DXMT **não** resolveram.

---

## ⚠️ ERROS DE MÉTODO QUE ME CUSTARAM A NOITE (não repetir)

1. **`pgrep -fc` NÃO EXISTE no macOS** (sem `-c`). Todas as contagens de processo
   que reportei como "morreu" eram mensagem de *usage*. A Steam estava viva em
   vários testes onde declarei que havia morrido.
   **Usar:** `pgrep -f pattern | wc -l`
2. **`WINEDEBUG=-all` silencia** exatamente as mensagens que eu queria contar.
   "0 erros" não significava nada. Usar `+seh` para crashes.
3. **`setsid` não existe no macOS** — um teste inteiro não rodou por isso.
   Usar `( nohup cmd & )` + `disown`.
4. **Loop `for` sem `sleep`** rodou 240 iterações em milissegundos sem esperar nada.
5. **Declarei "funcionou" com base em snapshot** favorável; o estado degradou depois.
6. **Desacreditei evidência real**: disse que a nota do assert `enum_tcp_connections
   sock.c` estava errada. **Não estava** — eu confundi esse assert (crash duro,
   observado no log de ontem) com o erro `10045` (benigno).

**Lição central:** o passo que achou a causa raiz foi **ler o crash**
(`WINEDEBUG=+seh`). Perdi horas trocando de Wine às cegas antes disso. Ler o erro
vem primeiro.

**`wineserver -p`** (persistente) evita que o prefix seja derrubado quando o
bootstrapper da Steam se encerra e relança o cliente.

---

## Problemas ainda em aberto (do handoff anterior)

- **Áudio robótico / calor** — `steamwebhelper` consome CPU alta. Conectado ao
  achado do VideoToolbox: decode por hardware deve ajudar. Minimizar a Steam
  derruba o webhelper.
- **VAC** — bloqueio de overlay causava erro; já revertido
  (`Bottle.disableSteamOverlay` default `false`).

## Suggested skills

- **systematic-debugging** — para a tela preta. *Ler o erro antes de trocar peça.*
- **brainstorming** — antes de qualquer feature nova.
- **handoff** — ao fim da próxima sessão.
