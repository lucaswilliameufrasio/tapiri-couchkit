# Plano — HomeDeck (ar condicionado + tomadas) e app companion

Status: **adiado**. Retomar quando o usuário conectar as tomadas e liberar o acesso à rede de IoT.

## Contexto levantado
- **Ar condicionado:** Midea/Springer Midea AI EcoMaster 18.000 BTU Inverter (modelos 42/38EZVQA18M5 quente/frio, 38EZVCA18M5 só frio). Tem Wi-Fi e usa o app SmartHome; a ficha lista compatibilidade com Alexa.
  - Fontes: https://www.midea.com.br/ar-condicionado-split-18000-btu-inverter-ai-ecomaster-preto-grafite-q-f-midea/p e https://www.buscape.com.br/ar-condicionado/ar-condicionado-split-hi-wall-springer-midea-ai-ecomaster-18000-btus-quente-frio-inverter-42ezvqa18m5-38ezvqa18m5 (a confirmar no manual: código exato do modelo e nome do app).
- **Alexa:** não tem API local; fica como controle de voz. Os aparelhos reais são controlados pelos drivers.
- **Tomadas inteligentes:** marca ainda desconhecida (provável Tuya/Smart Life). O controle local Tuya exige a *local key* de cada tomada.
- **Home Assistant:** o usuário não quer depender dele por enquanto. O app fala direto com os aparelhos.
- **Rede:** o ar condicionado está numa rede separada, só para IoT. O PC e o stick ficam na rede principal e não enxergam a de IoT. A descoberta por broadcast (UDP 6445) só funciona na mesma rede. Há uma regra do `ufw` aberta no PC para a LAN em UDP, que pode ser removida.

## Passos
1. **Acesso de rede:** obter o IP do ar condicionado e a faixa da rede de IoT. Opções, da mais simples: (a) regra no roteador liberando a rede principal para o IP do ar, porta TCP 6444; (b) stick na rede de IoT (perde ADB e go2rtc); (c) ponte com uma perna em cada rede. Testar com `ping` e abertura da porta 6444 a partir do PC.
2. **Protocolo Midea local (V2/V3):** validar do PC com o aparelho real: descoberta, token e chave, ler estado, ligar/desligar, modo, temperatura, ventilador. Tentar primeiro a conta compartilhada do `msmart-ng` para buscar o token pelo ID do aparelho; se não servir, o usuário roda localmente um script com o próprio login. Credenciais nunca passam pelo chat.
3. **Tomadas:** descobrir a marca e o app, obter a local key (Tuya), validar ligar/desligar e leitura de consumo, se houver.
4. **HomeDeck (TV):** app no padrão dos outros: servidor com token, QR na TV, página mobile web (Android e iPhone). Drivers por dispositivo (Midea, tomadas, depois Alexa/outros). Remoto: OK liga/desliga, ◀ ▶ ajustam a temperatura.
5. **Web:** a mesma página mobile serve como painel alternativo ao app dos fabricantes, tanto para o ar quanto para as tomadas.
6. **App companion (ao final):** cliente nativo para Android e iOS que descobre e controla os apps da TV (FireHome, PhoneBro, PhoneCast, StickHub, StickClock, HomeCam, HomeDeck) e os dispositivos. Recomendado Flutter (alternativa: KMP com Compose Multiplatform). Build de iOS exige macOS/Xcode (ou CI com runner macOS) e conta Apple; neste PC Linux só se gera a versão Android. Enquanto isso, as páginas web mobile cobrem os dois sistemas.
