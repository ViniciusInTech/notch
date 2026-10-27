<div align="center">
  <img src="Resources/AppIcon.png" width="112" alt="Ícone do Notch: uma ilha com ondas em tons de azul e lilás">
  <h1>Notch</h1>
  <p><strong>Sua música e seu tempo, no lugar certo.</strong></p>
  <p>Uma ilha dinâmica para macOS, com controles de música e Pomodoro integrado.<br>Discreta, personalizável e sem anúncios.</p>
  <p>macOS 14+ · Swift · SwiftUI + AppKit · Uso não comercial</p>
  <p>
    <a href="#por-que-criei-o-notch">A história</a> ·
    <a href="#em-funcionamento">Veja o app</a> ·
    <a href="https://github.com/ViniciusInTech/notch/raw/refs/heads/main/installers/Notch.dmg">Baixar para macOS</a> ·
    <a href="docs/SETUP.md">Configurar</a> ·
    <a href="CONTRIBUTING.md">Contribuir</a> ·
    <a href="DONATE.md">Apoiar via Pix</a>
  </p>
</div>

<p align="center">
  <img src="docs/assets/notch-music.png" width="900" alt="Captura real do Notch com capa do álbum, controles de música e Pomodoro em andamento na outra aba">
</p>

## Por que criei o Notch

Eu queria acompanhar meus ciclos de Pomodoro e descobrir qual música estava
tocando sem precisar ficar trocando de janela. Queria algo que ficasse ali,
à mão, mas sem ocupar espaço o tempo inteiro.

A ideia foi trazer para o Mac uma experiência parecida com a ilha dinâmica
do iPhone: discreta enquanto eu trabalho e útil assim que passo o mouse.
Foi assim que nasceu o Notch, juntando música e tempo em um único lugar.

Decidi disponibilizar o código para outras pessoas estudarem, adaptarem para
uso pessoal e ajudarem a melhorar o app. Encontrou um bug, teve uma ideia ou
quer deixar alguma parte melhor? Abra uma issue ou envie um pull request.

## Em funcionamento

### Discreto quando precisa ser

<p align="center">
  <img src="docs/assets/notch-compact.png" width="540" alt="Captura real da ilha recolhida, junto ao recorte da câmera do Mac">
</p>

A ilha cresce só para os lados quando há atividade. Ao passar o mouse, abre
os controles a partir do notch; ao retirar, recolhe suavemente. Os encaixes
superiores acompanham o formato do recorte do Mac.

### Seu Pomodoro continua, sua música também

<p align="center">
  <img src="docs/assets/notch-pomodoro.png" width="760" alt="Captura real da aba Pomodoro com uma sessão em andamento e controles de pausa e encerramento">
</p>

Trocar entre Música e Pomodoro não interrompe a outra atividade. Quando os dois
estão ativos, a ilha recolhida mostra os indicadores na ordem em que começaram.

*As imagens são capturas reais do aplicativo; as faixas e os tempos exibidos variam durante o uso.*

## O que o Notch faz

- **Música à mão:** capa, faixa, artista, reprodução, anterior/próxima e progresso.
- **Spotify sem conta extra:** integração com o app instalado, sem chave de API.
- **Navegador opcional:** mídia HTML5 da aba ativa do Safari ou Google Chrome.
- **Pomodoro integrado:** sessões de 25 minutos, pausas de 5 e pausa longa de 15 após quatro sessões.
- **Atividades simultâneas:** música e contagem continuam ao trocar de aba.
- **Ondas nas cores da capa:** animação decorativa, sem capturar ou analisar áudio.
- **Configurações nativas:** iniciar no login, reduzir movimento e som ao concluir.
- **Saída fácil:** botão Quit no painel e opção de sair pela barra de menus.

Sem anúncios, conta própria, telemetria, Electron ou servidor local. A prioridade
é manter uma experiência simples e discreta, com baixo consumo de recursos.

## Instalar

**[Baixar o instalador para macOS (.dmg)](https://github.com/ViniciusInTech/notch/raw/refs/heads/main/installers/Notch.dmg)**

[Opções de download e link direto](docs/DOWNLOAD.md)

**[Passo a passo: instalação, iniciar no login e permissões](docs/SETUP.md)**

O botão baixa o `.dmg` diretamente da pasta [`installers`](installers) deste
repositório, sem App Store. O arquivo de [checksums](installers/SHA256SUMS.txt)
permite conferir a integridade do download. Você também pode [compilar o app](#compilar-e-executar).

1. Encerre uma versão anterior pelo botão **Quit**. Conclua antes qualquer timer que queira preservar.
2. Abra o arquivo `.dmg` com dois cliques.
3. Arraste **Notch.app** para **Applications / Aplicativos**.
4. Ejete a imagem e abra o Notch pela pasta **Aplicativos**.

O app fica na barra de menus. Para iniciar com o Mac, abra as configurações e
habilite **Iniciar ao fazer login** depois de instalá-lo em Aplicativos.
Se o macOS pedir aprovação, use **Abrir Itens de Início**. O [guia completo](docs/SETUP.md#2-faça-o-notch-iniciar-junto-com-o-login)
mostra como conferir esse registro nos ajustes do sistema.

O instalador atual foi preparado para Macs com Apple Silicon. O projeto requer
macOS 14 ou superior. Builds Intel ainda não foram validados.

## Permissões e integrações

### Spotify

Abra o Spotify e inicie uma faixa. Se o macOS solicitar, autorize o Notch a
controlá-lo em **Ajustes do Sistema → Privacidade e Segurança → Automação**.
Não é necessário conectar uma conta pela web ou fornecer credenciais ao Notch.

### Safari e Google Chrome

Habilite **Mídia do navegador** nas configurações e escolha a fonte. Além da
permissão de Automação, é necessário permitir JavaScript via Apple Events:

- **Chrome:** Visualizar → Desenvolvedor → Permitir JavaScript de Eventos da Apple.
- **Safari:** habilite os recursos para desenvolvedores e a opção JavaScript de Eventos da Apple.

A integração consulta apenas a aba ativa da janela frontal do navegador escolhido.
Funciona com elementos `audio` e `video` HTML5 do documento principal. Iframes,
DRM, abas em segundo plano e players personalizados podem não funcionar.
Anterior/próxima são oferecidos no Spotify e no player do YouTube.

Não há integração universal com todo áudio do Mac. O conteúdo das páginas,
histórico e credenciais não são enviados a servidores pelo Notch.

### Pomodoro

Cada etapa é iniciada manualmente. Ao concluir uma sessão, a próxima pausa fica
pronta para começar; depois de quatro sessões, a pausa proposta é longa.
Também há um temporizador com duração personalizada nas configurações.

A contagem considera o horário absoluto: se o Mac dormir, o aviso é apresentado
quando ele acordar. Fechar o aplicativo encerra a sessão atual do timer.

## Compilar e executar

Instale Swift 6 e as Command Line Tools (`xcode-select --install`) ou use o Xcode.

```sh
git clone git@github.com:ViniciusInTech/notch.git
cd notch
./scripts/test.sh
./scripts/build.sh
open dist/Notch.app
```

Para gerar o instalador com atalho para Aplicativos:

```sh
./scripts/package-dmg.sh
```

Você também pode abrir `Package.swift` no Xcode ou usar `./scripts/run.sh`.
Use o `.app` empacotado para testar Automação e iniciar no login, pois ele possui
a identidade final do aplicativo.

O empacotamento local usa assinatura ad hoc. A distribuição pública com
Developer ID e notarização exige configuração própria; o script não faz notarização.

## Como o projeto está organizado

| Pasta | Responsabilidade |
| --- | --- |
| `Sources/NotchCore` | Geometria, tempo, Pomodoro, ordem de atividades e cores das capas. |
| `Sources/Notch` | Interface nativa, painel, configurações e integrações. |
| `Tests/NotchCoreTests` | Testes das regras do app. |
| `Resources` | Ícone, identidade e permissões do aplicativo. |
| `scripts` | Compilação, criação do ícone e empacotamento. |
| `docs` | Capturas, arquitetura e verificações manuais. |
| `.github` | CI, template de PR e link de apoio. |

Leia a [arquitetura](docs/architecture.md) e a [verificação manual](docs/manual-testing.md)
para entender os limites das integrações e dos testes. Os scripts do CI verificam
o projeto e geram o artefato macOS; não publicam releases automaticamente.

## Consumo de recursos

As ondas usam cinco camadas de Core Animation, com preferência de 24 quadros/s
e máximo de 30. Param ao expandir a ilha, pausar a música ou habilitar Reduzir
Movimento. A cor é extraída uma vez por capa, fora da interface, e fica em cache.

O Spotify usa eventos de reprodução e reconciliação periódica enquanto está
aberto. O navegador só é consultado quando a integração está habilitada e ele
está aberto. As consultas param durante a suspensão do Mac; respostas de
automação não bloqueiam a interface. Capas têm limites de download e cache.

O consumo real varia conforme o Mac e as integrações ativas. Não há promessa de
uma porcentagem fixa de CPU ou memória.

## Contribua

Melhorias e correções são bem-vindas. Você pode abrir uma
[issue](https://github.com/ViniciusInTech/notch/issues), fazer um fork ou enviar
um [pull request](https://github.com/ViniciusInTech/notch/pulls).

Consulte o [guia de contribuição](CONTRIBUTING.md). O objetivo é evoluir o app
com simplicidade, acessibilidade e cuidado com os recursos do Mac.

## Apoie o projeto

Se o Notch for útil para você e quiser apoiar o desenvolvimento, pode fazer
uma doação voluntária por Pix. Qualquer valor é bem-vindo; usar o app e contribuir
não depende de pagamento.

<p align="center">
  <a href="DONATE.md"><img src="docs/assets/pix-qr.png" width="190" alt="QR Code Pix para apoiar o desenvolvimento do Notch"></a>
</p>

**[Ver a chave e o Pix Copia e Cola](DONATE.md)**

## Licença

O código está disponível sob a **[PolyForm Noncommercial 1.0.0](LICENSE)**.
Você pode estudar, usar, modificar e compartilhar para fins não comerciais,
mantendo a licença e os [avisos de autoria](NOTICE).

A licença não concede permissão para vender o app, vender versões modificadas
ou usar seu código em produtos ou serviços comerciais pagos. Alterar o nome,
o visual ou parte do código não remove essas condições.

Por conter restrição comercial, o projeto é descrito como **código disponível
para uso não comercial (source-available)**. O texto integral da licença define
as permissões e condições; este resumo não o substitui.
