# Arquitetura

`NotchCore` não importa AppKit. `IslandLayout` define medidas em pontos;
`MediaSnapshot` representa leitura imutável da fonte e estima posição pelo horário;
`MediaSelection` prioriza fontes tocando; `Countdown` representa prazo absoluto
ou tempo pausado. Essas regras são exercitadas por Swift Testing.

`AppModel`, isolado na main actor, coordena ciclo de vida, preferências, timer e
integrações. Um único loop controla as consultas, interrompido durante suspensão.
`AutomationRunner` executa AppleScript fora da thread principal, com timeout e
processos serializados por fonte no coordenador. Nenhuma entrada é interpolada
como código sem codificação e os comandos aceitos são enums.

`IslandPanelController` usa NSPanel não ativante; a moldura é redimensionada para
o conteúdo realmente visível. A câmera continua livre: elementos compactos ficam
nas laterais da largura física do recorte. Monitores são recalculados após
mudanças de tela. `IslandView` só mantém uma atualização por segundo quando
exibe tempo em uso. Preferências usam UserDefaults, sem arquivos de configuração
ou dependências de terceiros.

O painel expandido usa 460 pontos de largura (ou a largura do notch mais 280),
limitado à largura da tela menos 16 pontos, e a altura do notch mais 96 pontos.
As laterais do notch, na faixa superior, recebem as abas (só ícones) à esquerda e
Configurações/Sair à direita. Música e Foco seguem a mesma estrutura: uma linha
principal (capa ou anel, título ou tempo, controles) e uma linha secundária
(progresso ou fases e sessões). As abas compartilham a área de controles, sem
interromper a reprodução ou o prazo do timer. O controle de volume foi removido da interface. O estado recolhido
continua com a altura física do notch; a mudança de tamanho ocorre apenas no hover
ou na abertura manual. `NotchOutline` desenha encaixes côncavos de 12 pontos no
topo, abrindo para fora e unindo a ilha à barra superior tanto recolhida quanto
expandida. A largura externa reserva 24 pontos para esses encaixes. Os cantos
inferiores usam raio de 12 pontos recolhida e 22 pontos expandida.

A moldura do NSPanel não é animada. Ao crescer, a janela assume na hora a união
do tamanho atual com o novo, transparente em volta da ilha; a forma preta
(`IslandGeometry.shapeSize`) cresce em SwiftUI com mola a partir do notch, para
baixo e para os lados, revelando o conteúdo de largura final centralizado. Ao
encolher, a forma anima e a janela só acompanha depois de 0,52 s. Fora da forma,
hitTest e as checagens de hover ignoram a área transparente. Abrir usa
spring(0,44; 0,74), alargar spring(0,36; 0,72) e recolher spring(0,32; 0,92). O hover espera 50 ms antes de abrir e 250 ms antes
de recolher. A checagem usa limites inclusivos com margem de 6 pontos (o cursor
preso na borda superior informa y == maxY) e mouseMoved reagenda a abertura se a
janela mudou de tamanho sob o ponteiro sem gerar mouseEntered.
A composição interna mantém a largura final
e é revelada pelo recorte, evitando remontar colunas durante a expansão.
O NSHostingView não impõe tamanho intrínseco à janela (sizingOptions vazio).
O controlador revela os controles após 120 ms. Cada bloco entra com opacidade,
desfoque e deslocamento de 8 pontos, escalonado a cada 40 ms; ao recolher, o
conteúdo some em 90 ms. A troca de abas usa indicador com matchedGeometryEffect
e transição com desfoque; dígitos usam numericText e play/pausa usa symbolEffect.
A tarefa de revelação é cancelada ao recolher, inclusive em hover rápido.
Não há animação contínua da moldura em repouso. “Reduzir movimento”, do app ou
do macOS, desativa a transição.

`AlbumWaveform` usa cinco CALayers com CAKeyframeAnimation decorativa e preferência
de 24 fps. Não há captura nem análise de áudio, display link ou timer por quadro.
A view é removida e a animação interrompida ao expandir a ilha; pausa e Reduzir
Movimento também interrompem o movimento; ao pausar, as barras desaceleram até
o repouso em 0,35 s. `ArtworkPalette` escolhe uma cor
dominante em uma amostra RGBA de 16 × 16 da capa, com brilho mínimo para contraste
no preto. A extração roda junto com a decodificação fora da main actor e o cache
armazena tanto a imagem quanto a cor. Sem capa, as ondas usam um tom neutro.

`SystemMediaProvider` lê o Tocando agora do macOS (MediaRemote), que cobre Música,
Spotify, navegadores e qualquer app da Central de Controle. Desde o macOS 15.4 o
MediaRemote só responde a processos assinados pela Apple, então `/usr/bin/perl`
carrega `libNotchMediaBridge.dylib` (alvo ObjC próprio, em Contents/Frameworks) e
chama `notch_media_stream`: a ponte registra as notificações de Tocando agora, sem
consulta periódica, e escreve uma linha JSON por mudança (capa em base64 só quando
muda, até 2 MB). Comandos (alternar, anterior, próxima, posição) voltam pela entrada
padrão; fechar a entrada encerra o helper. `MediaParser.nowPlaying` (núcleo) traduz a
linha. O helper só existe com a opção ligada e fora da suspensão; após três falhas
seguidas, a fonte é marcada com erro e Spotify e navegador voltam a ser consultados.
Com o Tocando agora ativo, os scripts de Spotify e navegador não rodam.
`SpotifyProvider` usa a interface AppleScript do Spotify e recebe eventos de
reprodução como indicação para reconciliar. `BrowserProvider` usa JavaScript
fixo em uma aba ativa opt-in. Falhas são apresentadas por fonte e bloqueiam novas
consultas até ação explícita quando necessário.

`LoginService` consulta o status real de SMAppService, sem marcar o toggle
como habilitado se o macOS não habilitou o serviço. Notificações locais são
opcionais e solicitadas quando o usuário inicia o primeiro temporizador.

`ActivityOrder` registra a ordem de ativação de música e timer. Com ambos ativos,
o notch preserva a câmera entre dois indicadores, com o mais antigo à esquerda.
O painel recolhido ganha 184 pontos laterais no total para acomodar ambos; a
mesma largura é usada para “etapa concluída” e “permissão pendente”, que mostram
ícone à esquerda e um rótulo curto à direita. A permissão pendente aparece só
quando a fonte com erro está aberta e nenhuma outra atividade está em andamento.
O anel de progresso do timer usa a duração total registrada ao iniciar.
`PomodoroCycle` alterna foco e pausas curtas e propõe a pausa longa após o número
de sessões de `PomodoroSettings` (padrão 25/5/15 min, 4 sessões); concluir a pausa
longa encerra o ciclo e zera as sessões. Com início automático, `AppModel` inicia
a etapa seguinte até o ciclo terminar. Não há item na barra de menus: o painel
abre Configurações e encerra o app.
Avisos de assistentes: `notch-hook` (alvo próprio, só Foundation) lê o JSON do
hook e envia `"<agente> <tamanho>\n" + JSON` ao socket Unix
`~/Library/Application Support/Notch/agents.sock` (0600, pasta 0700, peer
conferido com getpeereid). Sem socket, sai sem saída e o assistente segue
sozinho. `AgentHookServer` usa fila própria e DispatchSource; o socket só existe
com os avisos ligados e não pausados. Conclusões fecham a conexão na hora;
permissões a mantêm aberta até resposta, prazo ou fechamento pelo helper (lido
como abandono). `AgentHook`, no núcleo, traduz PermissionRequest/Stop (Claude
Code e Codex) e `stop` (Cursor) e gera a decisão. Sozinho, um aviso ocupa os dois
lados da ilha recolhida; com música, timer ou outro estado, vira uma bolinha à
direita. `IslandComposition` (núcleo) posiciona ilha, bolinha e mini chat a
partir do centro do notch: a janela é simétrica, o mini chat fica sob a bolinha
(ou centralizado) e as regiões definem hitTest e hover. O mini chat mede a
própria altura e a janela acompanha. Aberto, congela o prazo do aviso visível;
escolhas ou texto em andamento (`agentDraft`) o mantêm aberto. Perguntas
(AskUserQuestion) voltam como `updatedInput` com `answers`; recusa pode levar
mensagem. O hook de permissão espera até 1 h; o Notch decide antes pelo próprio
prazo. `AgentAlertMode` (núcleo) define o alerta de cada aviso novo: notificação do macOS com
som, sem som, ou silencioso (só a ilha). Permissões e perguntas sempre seguem o modo;
conclusões, só se “Alertar também nas conclusões” estiver ligado. O som é um
NSSound do sistema escolhido pelo usuário (padrão Ping), no máximo um a cada 1,5 s; a
notificação não leva som próprio, usa o id do aviso e é removida da Central quando o
aviso é resolvido. Eventos são registrados em `Logger` (subsistema dev.vinicius.Notch,
categoria agents). `AgentHookInstaller` edita os arquivos de hooks do usuário só
por ação explícita.
Chamadas: `CallMonitor` registra listeners de propriedade do HAL (CoreMediaIO
`DeviceIsRunningSomewhere` nas câmeras e CoreAudio no microfone padrão, opcional) em
fila própria, sem consulta periódica e sem acessar imagem ou áudio; só existe com os
avisos e o ajuste ligados. Em chamada, `CallAlertMode` (núcleo) troca o alerta por
silencioso ou notificação sem som, ou para o socket (pausar). A ilha mostra “Em chamada”
por 4 s, a bolinha ganha um sino cortado e, ao fim, pedidos que chegaram durante a
chamada tocam um único som se o modo normal tiver som.
Próxima reunião: `CalendarService` (actor com EKEventStore) lê eventos com horário das
próximas 12 h, sem dia inteiro, cancelados ou recusados, só após o usuário ligar a
Agenda (acesso total ao Calendário, pedido nesse momento). `MeetingLink` aceita só HTTPS
de serviços de vídeo conhecidos; `MeetingSchedule` mostra a reunião desde a antecedência
escolhida até 10 min após o início (ou o fim) e calcula a próxima mudança: `AppModel`
agenda uma única tarefa até ela, no máximo uma hora, e relê ao mudar o calendário
(EKEventStoreChanged). Com a Agenda ligada e o acesso indeterminado (um app assinado ad hoc
perde a permissão a cada build), o pedido é refeito uma vez por execução. Links sem esquema
("meet.google.com/…") ou http de serviços conhecidos abrem em HTTPS. Os passos ficam em
`Logger` (categoria meetings). Sozinha, a reunião ocupa as duas orelhas (título e “em N min” ou
“agora”); com música ou timer vira um calendário pequeno com os minutos na orelha direita.
Hover compacto (padrão): a ilha cresce só para os lados, `IslandLayout.compactWings`
(300 pontos no total), na altura do notch, com uma atividade e seus controles: reunião,
depois a atividade mais recente, Acordado ou música pausada. Sem atividade, o hover não
faz nada e o clique abre o painel. A largura final é mantida e revelada pela forma, como
no painel aberto. “Expandir para baixo” mantém o comportamento anterior.
Bandeja: `ShelfStore` guarda até 30 itens, mais recente primeiro, em UserDefaults.
Arquivos viram referências (bookmark que segue o original; se ele for apagado ou for
para o Lixo, o item some); só imagens, links (.webloc), textos e arquivos prometidos pelo
navegador viram cópias em `~/Library/Application Support/Notch/Shelf` (0700), apagadas
com o item. `Shelf` (núcleo) remove duplicatas e itens vencidos; uma única tarefa espera
o próximo vencimento. O NSHostingView aceita drops na região da ilha (ignorando arrastos
que saem da própria bandeja). A janela passa 1 ponto acima da borda da tela
(`IslandGeometry.edgeOverlap`, sem restrição de frame): o cursor preso na borda informa
y == maxY e, sem isso, o arrasto cairia no Mission Control. Os drops chegam a uma view
própria (conteúdo da janela, com o NSHostingView dentro), para o registro de arrasto do
SwiftUI não competir. Um monitor global de botão esquerdo (só recebe eventos com o botão
pressionado) percebe um arrasto de conteúdo pela mudança do pasteboard de arrasto e, a
180 pontos do topo perto do notch, abre a ilha para baixo na aba Bandeja com uma área de
soltar ocupando o painel: o arquivo é solto abaixo da borda, sem acionar o Mission
Control. Com histerese de 70 pontos em volta do painel, ela fecha quando o arrasto se
afasta ou termina em outro lugar; após um drop, fecha em 0,9 s mostrando o item novo.
Para fora, `ShelfDragCoordinator` é a fonte do arrasto e sobrevive ao recolher:
copia por padrão e move com ⌘ (ou o inverso); soltar em outro lugar tira o item da
bandeja (opção ligada por padrão). Uma cópia própria só é apagada um minuto depois,
porque o destino pode ainda estar copiando. Miniaturas
vêm do QLThumbnailGenerator fora da main actor; antes disso, o ícone do tipo. O hover
compacto alterna entre as atividades disponíveis com um botão próprio. Ao abrir a ilha,
a aba segue esta ordem: Bandeja, se recebeu itens nos últimos 10 minutos; senão a única
atividade em andamento (música tocando, timer, Acordado ou bandeja com itens); com mais
de uma, ou nenhuma, fica a última aba usada.
Prints e downloads: `FolderWatcher` usa um DispatchSource (kqueue) na pasta, em fila
própria, e só reporta nomes novos, visíveis e finalizados (`WatchedFile` ignora
.crdownload, .download etc.). Prints exigem o atributo kMDItemIsScreenCapture; a pasta
vem das preferências do screencapture (Mesa por padrão). Os watchers só existem com as
opções ligadas, e o macOS pede acesso à pasta nesse momento. Avisos transitórios
(`IslandNotice`) ocupam as orelhas por 3 a 5 s; o último download fica dois minutos no
hover compacto com Abrir, Mostrar no Finder e Guardar na bandeja.
Carregador: `PowerMonitor` observa a fonte de energia só com algum aviso ligado e em Macs
com bateria; `PowerEvents` (núcleo) decide entre conectado, desconectado, carga completa
e bateria fraca (cruzando 20% ou 10% na bateria), cada um visível por alguns segundos.
Manter acordado: `PowerAssertion` cria no próprio processo a asserção de energia
que o `caffeinate` usa (IOPMAssertionCreateWithName), PreventUserIdleDisplaySleep
ou, com “Permitir que a tela apague”, PreventUserIdleSystemSleep. Não há processo
auxiliar; o macOS libera a asserção se o app sair. `KeepAwakeSession` (núcleo)
guarda prazo absoluto ou nenhum; `AppModel` agenda uma única tarefa até o prazo,
cancelada na suspensão e reavaliada ao acordar. A fonte de energia só é observada
(IOPSNotificationCreateRunLoopSource) enquanto a asserção existe; com o corte
ligado, cair abaixo de 20% na bateria encerra o período, exceto se ele começou
abaixo disso. É a terceira aba da ilha aberta: anel, tempo e controle, com até
cinco atalhos, “Sempre” e “Outro” (quantidade em minutos, horas ou dias, até 30
dias), que troca a linha de atalhos por um campo na mesma altura; enquanto se
digita, a ilha não recolhe. Recolhida, sozinho ocupa os dois lados (xícara e tempo
ou ∞); com música ou timer, vira uma xícara pequena na borda externa da orelha
direita, ao lado das ondas ou do tempo. Com timer, a ilha usa as orelhas largas
para o relógio e a xícara caberem.
Teclas: `KeyTap` mantém dois CGEventTaps (exigem Acessibilidade) numa thread com
run loop própria, só com o HUD de volume e brilho ou os Copiados ligados. O tap fixo
recebe só NX_SYSDEFINED e mudanças de modificadores, nunca a digitação; o tap de
teclas fica desligado e só é habilitado enquanto o Command está pressionado, para
reconhecer ⌘C/⌘X. Eventos NX_SYSDEFINED de volume e brilho são traduzidos por
`MediaKey` (núcleo); `SystemAudio` altera o volume virtual e o mudo do dispositivo
de saída e `DisplayBrightness` usa DisplayServices (privado, carregado por dlopen)
na tela interna, ambos na thread do tap. O evento é consumido, então o HUD do macOS
não aparece; sem volume ajustável, sem tela interna ou sem o framework, a tecla
segue para o sistema. `LevelStep` dá 16 passos (64 com Shift e Option). O nível
fica 1,5 s na ilha, que cresce só para os lados; aberta, ele ocupa o lugar das
ações. Sem Acessibilidade, a notificação distribuída com.apple.accessibility.api
é observada até a permissão chegar.
Fones: `HeadphoneMonitor` registra notificações de conexão do IOBluetooth, filtra a
classe de áudio e lê a bateria por propriedades privadas do IOBluetoothDevice,
conferidas com respondsToSelector. A leitura acontece ao conectar (mais uma vez
3 s depois, se ainda vazia) e ao abrir o hover compacto; não há aviso de bateria
fraca porque exigiria consulta periódica. `HeadphoneBattery` ignora partes sem
leitura e resume pelo menor fone.
Copiados: `ClipboardStore` não consulta o NSPasteboard periodicamente. Lê o
changeCount 250 ms e 900 ms após ⌘C/⌘X vindos do tap e uma vez ao abrir a ilha;
cópias por menu só entram se ainda forem as mais recentes nesse momento. Leitura,
conversão para PNG e miniaturas rodam fora da main actor. `Clipboard` (núcleo)
remove repetidos, mantém fixados fora do limite e do prazo; o prazo é aplicado ao
abrir o painel, sem tarefa de espera. `ClipboardPolicy` descarta tipos
Concealed/Transient/AutoGenerated e apps ignorados. Imagens ficam em
`~/Library/Application Support/Notch/Clipboard` (0700); desligar apaga tudo.

O botão Quit usa NSApplication.terminate e o delegate cancela as tarefas do app.

A capa ocupa 50 × 50 pontos no painel aberto. Na ilha recolhida usa 22 pontos,
ou 20 com duas atividades. Miniaturas de até
256 pixels preservam definição em telas Retina, com cache de memória limitado.

O ícone é desenhado com primitivas vetoriais nativas em GenerateIcon.swift.
pack-icon.py grava as representações PNG em um contêiner ICNS padrão.
package-dmg.sh gera um fundo com a instrução de arrastar (GenerateDMGBackground.swift),
monta uma imagem gravável, aplica posição dos ícones e fundo pelo Finder e converte
para UDZO. Licença e avisos ficam dentro do app. Com CODE_SIGN_IDENTITY e
NOTARY_PROFILE, o app e o DMG são assinados com Developer ID e timestamp, enviados
ao notarytool e grampeados (docs/RELEASE.md). Sem eles, a assinatura é ad hoc.

`ApplicationMover` oferece, na primeira abertura, copiar o app para /Applications
quando ele roda de /Volumes, Downloads ou AppTranslocation (`InstallLocation`).
A cópia roda fora da main actor; uma versão anterior aberta é encerrada antes.
Um shell destacado, com caminhos como argumentos posicionais, espera o processo
atual sair, abre a nova cópia e ejeta o DMG. A opção pode ser desligada. A pasta installers guarda o arquivo público e
seu checksum, usados pelo botão de download no README.
