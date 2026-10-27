# tapiri-couchkit

Apps e ferramentas para controlar a TV do sofá: launcher, navegador controlado pelo celular, gerenciador de apps, cast, relógio e câmeras. Os apps são Android puro (min SDK 22, `LEANBACK_LAUNCHER`) e funcionam em Fire TV e Android TV. Testado em Fire TV Stick 4K (Fire OS 5 / Android 7.1) e em emuladores Android TV 7.1 e 16.

- `apps/` — apps da TV (genéricos). `companion/` — app Flutter (Android/iOS) que controla todos eles pelo celular. `firetv/` — scripts de otimização, **só para Fire OS**. `PLANO.md` — próximos passos.

- `firetv/apply.sh [disable|enable]` — debloat reversível (`firetv/debloat-list.txt`) + animações 0.5x.
- `apps/build.sh phonebro|firehome` — compila sem Gradle (aapt2+javac+d8+apksigner) → `apps/out/*.apk`.
- **PhoneBro**: navegador WebView; servidor HTTP na porta 8765, QR code na tela inicial (MENU mostra o QR). Cursor com D-pad, touchpad/teclado/URL/favoritos pelo celular.
- **FireHome**: launcher próprio; abre no boot (+12s). Home do controle continua indo para o launcher da Amazon (pacote protegido, sem root). Totalmente personalizável pelo celular (ver seção abaixo).
- `firetv/install-app.sh app.apk` — instala/atualiza apps de fora da loja **mantendo o ícone** no launcher oficial (ver abaixo).
- `firetv/rollback-launcher.sh` — reativa o launcher Amazon (caso necessário).
- `firetv/tune-official-launcher.sh [apply|revert]` — desliga anúncios personalizados, telemetria de uso e protetor de tela da Amazon; compila (`-m speed`) o launcher e as configurações.
- PhoneBro escolhe a porta sozinho (última usada → 8765..8805 → qualquer livre); a URL/QR mostra a porta real.
- **StickHub** (`release/stickhub.apk`): painel web (Android e iPhone) com lista de apps (abrir/encerrar/detalhes/desinstalar), envio e instalação de APK pelo celular, abrir link no PhoneBro, RAM/armazenamento e limpar RAM. Porta automática a partir de 8800, QR na tela da TV. Primeira instalação de APK exige liberar "fontes desconhecidas" para o StickHub.
- `release/` — APKs gerados localmente (não versionados). `emulator/` — AVDs `tv25` (Android 7.1) e `tv36` (Android 16).

## PhoneCast (`release/phonecast.apk`)
Envia do celular (Android ou iPhone) para a TV: links (vídeo/áudio direto tocam no player; YouTube e sites abrem no app correspondente), fotos, vídeos e músicas (upload, tocados na TV). Controles no celular: pausar, ±10 s, barra de posição, volume, mudo, fechar. No controle da TV: OK pausa, setas buscam, Voltar fecha. Porta automática a partir de 8850, QR code na tela inicial. Testado no emulador Android 7.1 (foto, vídeo, controles, link, parar).
Limite: em Android 10+ o sistema pode bloquear abrir o player com o app em segundo plano.

## StickClock (`release/stickclock.apk`)
Tela ambiente na TV: relógio grande, clima atual + 3 dias (Open-Meteo, sem chave; cidade definida pelo celular) e lista de notas/compras com checkbox. OK no controle mostra o QR; a página no celular (Android/iPhone) adiciona, marca, remove itens e muda a cidade. Porta automática a partir de 8900. Testado no emulador Android 16.

## HomeCam (`release/homecam.apk`)
Câmeras do go2rtc na TV. O endereço do go2rtc é definido pelo celular (MENU no controle mostra o QR). Grade com snapshots (`/api/frame.jpeg`), tela cheia em HLS via ExoPlayer/media3 1.3.1 (`/api/stream.m3u8`, libs em `apps/lib/media3/`) com queda automática para "modo compatível" (snapshots a ~5 fps) se o vídeo não iniciar em 8 s ou der erro; OK alterna os modos, ◀ ▶ trocam de câmera, Voltar fecha. Lista de câmeras vem de `/api/streams`. Porta automática a partir de 8950.
Teste sem câmeras reais: go2rtc com fontes `ffmpeg:virtual?video=testsrc2|smptebars|mandelbrot` (config usada: 3 streams h264 1280x720). No emulador Android 7.1 o HLS do go2rtc não tocava no VideoView nativo (fMP4); com ExoPlayer toca no stick real (decoder MTK AVC por hardware).

## Próximos apps (adiado)
Ver `PLANO.md`: HomeDeck (ar condicionado Midea + tomadas inteligentes) e app companion Android/iOS.

## Como compilar
```
apps/fetch-libs.sh        # baixa zxing e media3 (uma vez)
apps/build.sh homecam     # gera apps/out/homecam.apk (assina com apps/debug.keystore, criado na 1a vez)
```
Requer Android SDK (build-tools 36, android-34) e JDK. A keystore de debug é gerada localmente e **não** vai para o git: se perdê-la, os apps precisam ser reinstalados (assinatura diferente). Os scripts de `firetv/` leem `STICK=ip:5555` do ambiente ou de um `.env` (copie `.env.example`).

## Primeira instalação só com o celular

1. No PC: `python3 tools/dist.py --build --tv` (compila e mostra o endereço e o QR).
2. No celular, abra o QR e instale o Couchkit.
3. Na TV, instale o app **Downloader** (loja da Amazon), abra-o e digite o endereço
   `IP:porta/h?k=token` que o script imprime na linha "Fire TV". Isso baixa o **StickHub**.
4. Abra o StickHub na TV, aperte MENU e escaneie o QR no Couchkit. Um QR basta: os apps da TV
   compartilham o token do StickHub (permissão de assinatura) e o Couchkit encontra os outros sozinho.
5. Pelo Couchkit (Início → Instalar APK) mande os demais APKs de `dist/tv/` para a TV.

Depois disso o PC só é preciso para atualizar os apps. A otimização profunda ainda usa `firetv/`.

## Companion (Flutter)
Ver `companion/README.md`. Pareia pelo QR da TV, guarda o token no Keychain/Keystore e reencontra o app se a porta mudar. Build: `cd companion && make check && make apk`.

## Distribuição local (APK/IPA pela rede)
```
tools/dist.py --build            # compila o companion (APK arm64) e serve
tools/dist.py --build --tv       # idem, e também os apps da TV
tools/dist.py --ipa app.ipa      # inclui um IPA gerado no Mac
```
Sobe um servidor local, lista os endereços de cada interface de rede e mostra um QR code para abrir no celular (precisa de `qrencode` para o QR no terminal). Todo acesso exige o token da sessão (`?k=`). No Android é um download direto. No iPhone a instalação é OTA (`itms-services`) por HTTPS: o script cria uma CA local em `~/.cache/couchkit-dist/` (fora do repositório), a página oferece o certificado para instalar e confiar, e o IPA precisa estar assinado com um perfil que inclua o UDID do aparelho (e Modo Desenvolvedor ativo no iOS 16+). O build do IPA em si exige macOS.

## FireHome personalizável
MENU no controle (ou o tile "Personalizar") mostra um QR code com o endereço e o token (`http://IP:porta/?k=token`, porta automática a partir de 9000). Pelo celular, na página web (Android e iPhone) ou na tela FireHome do companion, dá para mudar com prévia ao vivo: tema (presets, cores do fundo e de destaque, cantos, tamanho dos cartões e do texto), papel de parede (com escurecimento), cabeçalho (relógio 12/24 h, data, RAM, saudação e clima por cidade), linhas da tela (ordem, visibilidade, cartões grandes, linhas personalizadas com apps escolhidos), favoritos (ordem), apps (esconder e renomear) e as ferramentas da linha Sistema. A configuração é um JSON validado no servidor (tipos e cores inválidos voltam ao padrão) e fica em `SharedPreferences`. API (todas exigem `?k=`): `GET/POST /api/config`, `/api/apps`, `/api/icon`, `/api/preview` (JPEG da tela), `POST /api/wallpaper`, `/api/wallpaperclear`, `/api/reset`.

## Ícone sumido no launcher oficial (Fire OS)
Apps instalados fora da loja perdem o ícone na grade "Seus aplicativos e jogos" quando são **atualizados** com `adb install -r` (o log mostra `AmazonAppstore.SideloadedAppManagerService: cannot update entry for package`). Desinstalar com `pm uninstall -k` (mantém os dados) e instalar de novo recria o registro e o ícone volta. Use `firetv/install-app.sh`. Atualizações feitas pelo StickHub (PackageInstaller) têm o mesmo limite.

## Otimizar pelo celular (ADB)

O Couchkit fala ADB direto com a TV (`IP:5555`), como o PC faria, então aplica os ajustes de
`firetv/` sem PC (Início → Otimizar a TV): animações, debloat, privacidade, limpar cache e
compilar. Exige a Depuração ADB ligada e **uma** autorização na TV para a chave do celular
(marque "Sempre permitir"; a janela só aparece enquanto o app espera). A chave RSA fica no
armazenamento seguro do celular.

O adbd da Fire OS aceita um cliente por vez e recusa conexões que partem da própria TV, por isso
o cliente é o celular. Com o ADB do PC conectado, rode `adb disconnect` antes.
`tools/fake_adbd.py` é um adbd falso que confere a assinatura e o formato da chave, para testar
o cliente sem aparelho.
