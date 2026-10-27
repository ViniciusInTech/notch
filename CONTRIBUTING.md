# Contribuindo com o Notch

O Notch nasceu de uma necessidade pessoal e pode ficar melhor com a comunidade.
Correções, sugestões, traduções, melhorias de acessibilidade e contribuições de
código são bem-vindas.

## Antes de começar

Para uma mudança grande, abra uma [issue](https://github.com/ViniciusInTech/notch/issues)
e explique o problema e a proposta. Para uma correção pequena, pode seguir direto
com um pull request.

Leia o [README](README.md) e a [arquitetura](docs/architecture.md). O app é nativo
para macOS 14 ou superior, em Swift, sem dependências externas de runtime.

## Preparar o ambiente

1. Faça um fork do repositório e trabalhe em uma branch própria.
2. Abra `Package.swift` no Xcode ou use as Command Line Tools.
3. Execute `./scripts/test.sh` e `./scripts/build.sh`.
4. Teste o app empacotado em `dist/Notch.app`, especialmente as permissões de Automação.

## Enviar um pull request

Explique o problema, o comportamento esperado e como você validou a solução.
Se mudar a interface, inclua capturas antes/depois. Para regressões, acrescente
um teste que demonstre o problema quando isso for apropriado.

Mantenha as alterações focadas. A prioridade é um app discreto, simples e leve:
evite consultas desnecessárias, animações em repouso e trabalho pesado na interface.
Preserve as opções de acessibilidade e Reduzir Movimento.

Não inclua credenciais, dados pessoais de terceiros, caches, builds ou certificados.
Use a [lista de verificação manual](docs/manual-testing.md) para recursos que
dependem da sessão gráfica, das fontes de mídia e das permissões do macOS.

## Licença das contribuições

Ao enviar uma contribuição, você declara ter o direito de disponibilizá-la sob
a mesma [PolyForm Noncommercial 1.0.0](LICENSE) do projeto. Você mantém a autoria
da sua contribuição; ela deve respeitar as mesmas condições de uso não comercial.

É permitido estudar, modificar e compartilhar o Notch para fins não comerciais,
mantendo a licença e os avisos. A licença não permite vender o app ou derivados,
nem incorporar seu código em uma oferta comercial paga sem autorização específica.

Não é necessário doar para usar o app, abrir issues ou enviar PRs.
