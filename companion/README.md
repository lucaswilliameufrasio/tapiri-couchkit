# Couchkit Remote

App companion (Flutter, Android e iOS) para os apps do tapiri-couchkit que rodam na TV: PhoneBro, StickHub, PhoneCast, StickClock e HomeCam.

## Como funciona
1. Na TV, abra um app e aperte MENU para ver o QR code (com `?k=token`).
2. No companion, **Adicionar** e escaneie o QR (ou cole o endereço). O app descobre qual app da TV é pelo `<title>` da página e guarda o token no Keychain/Keystore.
3. Se a TV reiniciar um app em outra porta, o companion varre a faixa de portas do app e se reconecta sozinho.

Telas: navegador com touchpad e teclado (PhoneBro), apps/RAM/instalar APK (StickHub), enviar link/foto/vídeo e controlar a reprodução (PhoneCast), cidade e lista (StickClock) e endereço do go2rtc (HomeCam).

## Desenvolvimento
Flutter 3.47.8 via FVM (`.fvmrc`).
```
fvm install            # uma vez
make get
make check             # formata, analisa e testa
make apk               # build/app/outputs/flutter-apk/app-release.apk
```
O build de iOS precisa de macOS/Xcode: `fvm flutter build ios`.

## Estrutura
```
lib/core/      logger, injeção de dependências, rotas, cliente HTTP da TV
lib/data/      modelos, armazenamento seguro, repositório e serviços por app
lib/features/  telas (home, add, phonebro, hub, cast, clock, cam)
```
Fluxo: tela → serviço/repositório → `TvClient`. As telas não chamam HTTP diretamente.

## Limites
- Só HTTP na rede local; o token é a única barreira. Não exponha as portas à internet.
- No iOS é preciso aceitar a permissão de rede local na primeira vez.
