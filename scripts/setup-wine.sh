#!/usr/bin/env bash
# setup-wine.sh — prepara o runtime open source para o MacStrike.
#
# Uso:
#   bash scripts/setup-wine.sh            # baixa o Wine (Gcenx) automaticamente
#   bash scripts/setup-wine.sh --gptk     # só mostra as instruções do Apple GPTK
#   bash scripts/setup-wine.sh --channel devel   # usa wine-devel em vez de staging
#
# O MacStrike (motor em Swift) NÃO embute Wine nem as DLLs de tradução: ele aponta
# para uma instalação open source, que este script monta em:
#   ~/Library/Application Support/MacStrike/wine   (deve conter bin/wine)
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/MacStrike"
WINE_ROOT="$SUPPORT/wine"
DOWNLOADS="$SUPPORT/downloads"
CHANNEL="staging"          # staging | devel
MODE="auto"
GCENX_REPO="Gcenx/macOS_Wine_builds"

while [ $# -gt 0 ]; do
  case "$1" in
    --gptk)     MODE="gptk" ;;
    --channel)  CHANNEL="${2:-staging}"; shift ;;
    -h|--help)  MODE="help" ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$WINE_ROOT" "$DOWNLOADS" "$SUPPORT/dlls"

print_gptk() {
  cat <<EOF
=== Apple Game Porting Toolkit (melhor desempenho; precisa de Apple ID) ===
O GPTK traz o Wine otimizado da Apple + D3DMetal (D3D11/12 -> Metal).
  1. Baixe "Game Porting Toolkit" em  https://developer.apple.com/download/all/
  2. Monte o .dmg; dentro há o Wine (bin/ lib/ lib64/) e o D3DMetal.
  3. Copie a árvore do Wine para:  "$WINE_ROOT"   (precisa de bin/wine64)
  4. D3DMetal: copie as DLLs para "$SUPPORT/dlls/d3dmetal/x86_64-windows/" e o
     libd3dshared.dylib para "$WINE_ROOT/lib64/apple_gptk/external/".
EOF
}

if [ "$MODE" = "help" ] || [ "$MODE" = "gptk" ]; then
  print_gptk
  exit 0
fi

# ---------------------------------------------------------------------------
# Download automático do Wine (Gcenx) — x86_64, roda sob Rosetta no Apple Silicon
# ---------------------------------------------------------------------------
echo "MacStrike :: setup do Wine ($CHANNEL) a partir de $GCENX_REPO"
echo "  WINE_ROOT = $WINE_ROOT"

if [ -x "$WINE_ROOT/bin/wine64" ] || [ -x "$WINE_ROOT/bin/wine" ]; then
  echo "Wine já presente em $WINE_ROOT/bin — nada a fazer. (apague a pasta para reinstalar)"
  exit 0
fi

echo "Consultando a última release..."
API="https://api.github.com/repos/$GCENX_REPO/releases/latest"
ASSET_URL=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API" \
  | python3 -I -c "
import sys,json
d=json.load(sys.stdin)
ch='$CHANNEL'
cands=[a for a in d.get('assets',[]) if a['name'].endswith('.tar.xz')]
pick=[a for a in cands if ('wine-%s-'%ch) in a['name']] or cands
if not pick:
  sys.exit('nenhum asset .tar.xz encontrado')
print(pick[0]['browser_download_url'])
")
echo "  asset: $ASSET_URL"

TARBALL="$DOWNLOADS/$(basename "$ASSET_URL")"
echo "Baixando (~190 MB)..."
curl -fL --progress-bar -o "$TARBALL" "$ASSET_URL"

echo "Extraindo..."
STAGING="$DOWNLOADS/wine-extract"
rm -rf "$STAGING"; mkdir -p "$STAGING"
tar xJf "$TARBALL" -C "$STAGING"

# Localiza o diretório que contém bin/wine (dentro do .app o Wine fica em
# Contents/Resources/wine).
WINE_SRC_BIN=$(find "$STAGING" -type f -name wine -path "*/bin/wine" | head -1)
if [ -z "$WINE_SRC_BIN" ]; then
  echo "ERRO: não encontrei bin/wine no arquivo extraído." >&2
  exit 1
fi
WINE_SRC_DIR=$(cd "$(dirname "$WINE_SRC_BIN")/.." && pwd)   # .../wine
echo "  origem: $WINE_SRC_DIR"

echo "Instalando em $WINE_ROOT..."
rm -rf "$WINE_ROOT"; mkdir -p "$WINE_ROOT"
# -a preserva symlinks/permissões; copia o conteúdo da árvore do Wine.
cp -a "$WINE_SRC_DIR"/. "$WINE_ROOT"/
rm -rf "$STAGING"

echo
if [ -x "$WINE_ROOT/bin/wine64" ] || [ -x "$WINE_ROOT/bin/wine" ]; then
  echo "OK: Wine instalado em $WINE_ROOT/bin"
  echo "    export MACSTRIKE_WINE_ROOT=\"$WINE_ROOT\""
  echo
  echo "Próximo: swift run macstrike fetch-dxmt   (baixa o DXMT e coloca winemetal.so aqui)"
  echo
  echo "Nota: este Wine (Gcenx) é uma base geral sólida. Para o DXMT especificamente,"
  echo "o projeto 3Shain recomenda o Wine deles ou o do GPTK; se o DXMT não carregar,"
  echo "troque o WINE_ROOT pelo GPTK (rode: bash scripts/setup-wine.sh --gptk)."
else
  echo "ERRO: instalação terminou sem bin/wine." >&2
  exit 1
fi
