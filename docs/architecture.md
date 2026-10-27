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

O painel expandido usa 480 × 214 pontos, limitado à largura da tela menos 16 pontos.
As abas Música e Pomodoro compartilham a área de controles, sem interromper
a reprodução ou o prazo do timer. O controle de volume foi removido da interface. O estado recolhido
continua com a altura física do notch; a mudança de tamanho ocorre apenas no hover
ou na abertura manual. `NotchOutline` desenha encaixes côncavos de 12 pontos no
topo, abrindo para fora e unindo a ilha à barra superior tanto recolhida quanto
expandida. A largura externa reserva 24 pontos para esses encaixes; o conteúdo
continua com 480 pontos. Os cantos inferiores usam raio de 24 pontos ao expandir.

A abertura anima a moldura real do NSPanel por 0,42 s a partir do topo central
do notch, com aceleração suave; o recolhimento mantém a curva anterior de 0,28 s.
A composição interna mantém a largura final
e é revelada pelo recorte, evitando remontar colunas durante a expansão.
O NSHostingView não impõe tamanho intrínseco à janela (sizingOptions vazio),
evitando que o conteúdo de largura fixa antecipe o tamanho final antes da animação.
O controlador revela os controles após 100 ms, com fade curto, sem zoom na entrada.
A tarefa de revelação é cancelada ao recolher, inclusive em hover rápido.
Não há animação contínua da moldura em repouso. “Reduzir movimento”, do app ou
do macOS, desativa a transição.

`AlbumWaveform` usa cinco CALayers com CAKeyframeAnimation decorativa e preferência
de 24 fps. Não há captura nem análise de áudio, display link ou timer por quadro.
A view é removida e a animação interrompida ao expandir a ilha; pausa e Reduzir
Movimento também interrompem o movimento. `ArtworkPalette` escolhe uma cor
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
O painel recolhido ganha 184 pontos laterais no total para acomodar ambos.
`PomodoroCycle` controla sessões de 25 min, pausas de 5 min e pausa longa de
15 min após quatro sessões. A próxima fase fica pronta, sem início automático.
O botão Quit usa NSApplication.terminate e o delegate cancela as tarefas do app.

A capa ocupa 92 × 92 pontos no painel aberto, mantendo as dimensões existentes.
Na ilha recolhida usa 26 pontos, ou 23 com duas atividades. Miniaturas de até
256 pixels preservam definição em telas Retina, com cache de memória limitado.

O ícone é desenhado com primitivas vetoriais nativas em GenerateIcon.swift.
pack-icon.py grava as representações PNG em um contêiner ICNS padrão.
package-dmg.sh empacota o app assinado ad hoc e o link Applications num DMG,
incluindo a licença e os avisos. A pasta installers guarda o arquivo público e
seu checksum, usados pelo botão de download no README.
