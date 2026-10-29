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
prazo. Eventos são registrados em `Logger` (subsistema dev.vinicius.Notch,
categoria agents). `AgentHookInstaller` edita os arquivos de hooks do usuário só
por ação explícita.
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
