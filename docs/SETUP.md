# Instalação e configuração do Notch

[Baixar o instalador](DOWNLOAD.md) · [Voltar ao projeto](../README.md)

## 1. Instale em Aplicativos

1. Baixe o `.dmg` pela [página de download](DOWNLOAD.md).
2. Se uma versão anterior estiver aberta, conclua o timer e clique em **Quit**.
3. Abra o `.dmg` com dois cliques.
4. Arraste **Notch.app** para **Applications / Aplicativos**.
5. Ejete o disco Notch no Finder.
6. Abra **Aplicativos → Notch**. Use essa cópia no dia a dia.

O Notch aparece na barra de menus e junto ao recorte da câmera. Passe o mouse
para expandir ou abra **Notch → Abrir ilha** pelo menu.

A versão de desenvolvimento usa assinatura ad hoc e não é notarizada. O macOS
pode solicitar uma confirmação adicional na primeira abertura. Consulte as
[orientações da Apple sobre abrir apps com segurança](https://support.apple.com/pt-br/102445)
para avaliar a origem e a autorização do aplicativo.

## 2. Faça o Notch iniciar junto com o login

1. Com o Notch já instalado em Aplicativos, abra seu menu na barra superior.
2. Entre em **Configurações… → Geral**. O ícone de engrenagem do painel também abre essa janela.
3. Ative **Iniciar ao fazer login**.
4. Se aparecer um pedido de aprovação, clique em **Abrir Itens de Início** e aprove o Notch.
5. Para conferir no macOS, abra **Ajustes do Sistema → Geral → Itens de Início e Extensões**.
6. Verifique se o Notch está em **Abrir ao Iniciar Sessão**. Os nomes podem variar com o idioma e a versão do sistema.

O toggle reflete o status informado pelo macOS. Se continuar desligado, confira
a mensagem na própria janela antes de tentar de novo. Mantenha o app no mesmo
local depois de habilitar a opção. Para parar a abertura automática, desligue-a
nas configurações do Notch ou remova o item nos ajustes do sistema.

Veja também o [guia oficial de itens de início](https://support.apple.com/pt-br/guide/mac-help/mh15189/mac).

## 3. Autorize o Spotify

1. Abra o Spotify e comece a tocar uma música.
2. No Notch, entre em **Configurações… → Conexões** e deixe **Integrar com Spotify** ligado.
3. Quando o macOS pedir autorização para o Notch controlar o Spotify, escolha **Permitir**.
4. Se a permissão foi negada antes, abra **Ajustes do Sistema → Privacidade e Segurança → Automação**.
5. Localize **Notch** e habilite **Spotify** dentro dele.
6. Volte às conexões do Notch e clique em **Tentar novamente**.

Se o Notch ainda não aparecer em Automação, abra os dois aplicativos e tente
a conexão para que o macOS receba o primeiro pedido. Não é preciso informar
senha do Spotify, token ou chave de API ao Notch.

Referência: [controle de outros apps no macOS](https://support.apple.com/pt-br/guide/mac-help/mchl07817563/mac).

## 4. Habilite o navegador, se quiser

Essa integração é opcional e fica desligada inicialmente. Lê somente mídia
HTML5 acessível na aba ativa da janela frontal do navegador escolhido.

### Google Chrome

1. Abra **Configurações… → Conexões** no Notch.
2. Ligue **Mídia do navegador** e escolha **Google Chrome**.
3. Na barra de menus do Chrome, abra **Visualizar → Desenvolvedor → Permitir JavaScript de Eventos da Apple**.
   Em inglês: **View → Developer → Allow JavaScript from Apple Events**.
4. Autorize o Notch a controlar o Chrome no pedido do macOS. A permissão também fica em **Privacidade e Segurança → Automação**.
5. Abra a aba com o vídeo ou áudio e inicie a reprodução.
6. Clique em **Tentar novamente** nas conexões do Notch.

Esse requisito é documentado pelo [projeto Chromium](https://www.chromium.org/developers/applescript/).

### Safari

1. Escolha **Safari** nas conexões do Notch e ligue **Mídia do navegador**.
2. No Safari, abra **Ajustes → Avançado** e habilite os recursos para desenvolvedores.
3. Nas opções de desenvolvedor/automação, habilite **Permitir JavaScript de Eventos da Apple**.
   Em inglês: **Allow JavaScript from Apple Events**. A localização varia entre versões do Safari.
4. Autorize o Notch a controlar o Safari em **Privacidade e Segurança → Automação**.
5. Inicie um vídeo ou áudio na aba ativa e clique em **Tentar novamente** no Notch.

Consulte as [opções de desenvolvedor do Safari](https://developer.apple.com/documentation/safari-developer-tools/developer-settings).

Players dentro de iframes, conteúdo protegido e alguns sites podem não ser
compatíveis. Abas em segundo plano não são monitoradas. Você pode desligar a
integração do navegador quando não quiser utilizá-la.

## 5. Configure os avisos do Pomodoro

1. Abra a aba **Pomodoro** e inicie uma sessão.
2. Se o macOS perguntar, permita as notificações do Notch.
3. Para alterar isso depois, use **Ajustes do Sistema → Notificações → Notch**.
4. Para o aviso sonoro do próprio app, use **Configurações… → Geral → Som ao terminar temporizador**.

A permissão de notificação é opcional: a contagem funciona mesmo sem banners.
Cada etapa do Pomodoro é iniciada manualmente. Fechar o app encerra a contagem atual.

## Quais permissões são necessárias?

| Recurso | O que habilitar |
| --- | --- |
| Spotify | Automação para controlar o Spotify. |
| Safari/Chrome | Automação para o navegador escolhido e JavaScript via Apple Events. |
| Abrir no login | Iniciar ao fazer login; aprovação nos Itens de Início, se solicitada. |
| Aviso visual do timer | Notificações do Notch, se desejar banners. |

Essas funções não exigem Microfone, Gravação de Tela ou Acesso Total ao Disco.
As ondas são decorativas e não capturam áudio.

## Soluções rápidas

| O que aconteceu | O que conferir |
| --- | --- |
| Nada aparece depois de abrir | Procure o ícone na barra de menus e use **Abrir ilha**. |
| Não iniciou após o login | App em Aplicativos, toggle ligado e aprovação do sistema concluída. |
| Faixa/capa não aparece | Música tocando, app Spotify aberto, integração ligada e Automação permitida. |
| Navegador não responde | Navegador correto, aba ativa, mídia HTML5 e JavaScript via Apple Events habilitado. |
| Permissão negada | Ajuste Automação e pressione **Tentar novamente**. |
| App atualizado, mas interface antiga | Use **Quit** na versão anterior e abra a cópia nova em Aplicativos. |
| Timer está correto, mas sem banner | Confira Notificações e os modos Foco/Não Perturbe do macOS. |

Se continuar acontecendo, abra uma [issue](https://github.com/ViniciusInTech/notch/issues)
com a versão do macOS, a fonte de mídia e o que você tentou. Remova informações
pessoais de capturas e mensagens antes de enviá-las.
