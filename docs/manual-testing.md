# Verificação manual

Os testes automatizados cobrem domínio e parsing. A integração com apps,
permissões e sessão gráfica exige os cenários abaixo. Os itens marcados foram
verificados durante o desenvolvimento; repita-os para cada versão relevante.

## Empacotamento

- [x] Build release concluído, assinatura ad hoc e Info.plist verificados.
- [x] Ícone PNG/ICNS reconhecido pelo macOS.
- [x] Imagem DMG aberta com dois cliques, contendo app e atalho Applications.
- [ ] Instalar em Aplicativos num segundo Mac compatível.
- [ ] Conferir a experiência de primeira abertura em um Mac sem permissões anteriores.
- [x] Janela do DMG com fundo, seta e ícones posicionados.
- [ ] Abrir pelo DMG e aceitar "Mover para Aplicativos": cópia, reabertura e ejeção.
- [ ] Mover com uma versão anterior aberta: a anterior é encerrada e substituída.
- [ ] DMG assinado, notarizado e grampeado abre só com a confirmação padrão.

## Manter acordado

- [ ] `pmset -g assertions` mostra “Notch: manter acordado” ao ligar e some ao desligar, terminar o prazo ou sair do app.
- [ ] Com “Permitir que a tela apague”, a asserção vira PreventUserIdleSystemSleep.
- [ ] “Outro” aceita minutos, horas e dias; a ilha não recolhe enquanto se digita.
- [ ] Recolhida: xícara e tempo sozinho; xícara pequena com música, timer ou ambos, sem cortar o tempo.
- [ ] Na bateria, abaixo de 20%, o corte encerra o período quando habilitado.

## Interface e atividades

- [x] Painel compacto, com abas Música e Pomodoro e sem controle de volume.
- [x] Capa, título, artista e progresso reais do Spotify exibidos.
- [x] Música e timer continuam ao trocar de aba.
- [x] Tempo restante aparece na aba e na ilha recolhida.
- [x] Botão Quit encerra o app.
- [ ] Conferir as duas ordens de início no notch com música e timer reais.
- [ ] Conferir abertura contínua a partir do recorte, sem salto para o tamanho final.
- [ ] Passar e retirar o mouse rapidamente sem flicker ou controles presos.
- [ ] Passar de raspão pela ilha (menos de 80 ms) não abre o painel.
- [ ] Abertura com leve quique, conteúdo entra escalonado com desfoque.
- [ ] Indicador das abas desliza; dígitos do timer rolam; play/pausa se transforma.
- [ ] Etapa concluída e permissão pendente na ilha recolhida.
- [ ] Arrastar na barra de progresso faz seek; a barra engrossa no hover.
- [ ] Conferir encaixes côncavos do topo e cantos inferiores em fundos claros e escuros.
- [ ] Confirmar que hover e recolhimento preservam o foco do app anterior.
- [ ] Conferir tela cheia, Spaces e conectar/desconectar monitores.
- [ ] Conferir o comportamento em tela sem notch.

## Reprodução e permissões

- [ ] Reproduzir, pausar, anterior/próxima e seek no Spotify.
- [ ] Confirmar mudança de capa e título ao trocar de faixa.
- [ ] Fechar a fonte de mídia e conferir o estado ocioso.
- [ ] Negar Automação: mostrar orientação sem repetir pedidos continuamente.
- [ ] Autorizar novamente e usar Tentar novamente para recuperar a integração.
- [ ] Safari e Chrome: aba ativa com áudio/vídeo HTML5, seek e pausa.
- [ ] Navegador sem JavaScript via Apple Events: mostrar orientação nas conexões.
- [ ] Fonte tocando tem prioridade sobre uma pausada; Spotify vence se ambas tocam.

## Pomodoro e temporizador

- [x] Iniciar e encerrar timer pela interface.
- [ ] Pausar, retomar e concluir uma etapa completa.
- [ ] Conferir notificação e som de conclusão sem avisos duplicados.
- [ ] Conferir a próxima fase após quatro sessões e após a pausa longa.
- [ ] Conferir contagem após dormir/acordar o Mac.
- [ ] Negar notificações e confirmar que a contagem segue funcionando.
- [ ] Conferir temporizador personalizado nas configurações.

## Assistentes

- [ ] Instalar e remover o hook de Claude, Codex e Cursor sem perder outros hooks.
- [ ] Pedido de permissão do Claude Code: Permitir e Recusar pela ilha.
- [ ] Deixar o prazo expirar e conferir o pedido no terminal.
- [ ] Responder no terminal e conferir que o aviso some da ilha.
- [ ] Conclusão de Claude, Codex e Cursor com a última resposta.
- [ ] Pausar pelo sino: nenhum aviso chega e os assistentes seguem normalmente.
- [x] Com música tocando, o aviso aparece numa bolinha à direita sem tirar a música.
- [x] Hover na bolinha abre o mini chat; prazo congela enquanto aberto.
- [x] Pergunta com opções devolve `answers` (teste com `notch-hook`).
- [ ] Pergunta e plano numa sessão real do Claude Code.
- [ ] Recusar com instrução escrita e conferir a mensagem no Claude Code.

## Aparência, login e recursos

- [ ] Capas de cores distintas atualizam a cor das ondas.
- [ ] Ondas se movem só com reprodução e ilha recolhida.
- [ ] Expandir, pausar ou habilitar Reduzir Movimento interrompe as ondas.
- [ ] Sem capa, usar cor neutra com contraste no fundo preto.
- [ ] Desabilitar hover mantém a abertura por clique disponível.
- [ ] Iniciar no login reflete o estado do macOS; desabilitar remove o registro.
- [ ] Medir ocioso, Spotify e navegador no Monitor de Atividade por alguns minutos.

Não marque cenários gráficos como concluídos apenas porque os testes ou o build passaram.
