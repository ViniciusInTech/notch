# Notch

- Aplicativo pessoal nativo para macOS 14+, Swift Package sem dependências externas.
- Leia `docs/architecture.md` e o README antes de alterar integrações.
- Testes: `./scripts/test.sh`. Build do app: `./scripts/build.sh`.
- Preserve ociosidade sem processos de automação quando as fontes estiverem fechadas.
- Estado ativo cresce somente para os lados; somente a expansão manual/hover cresce para baixo.
- Nenhuma rotina de rede, automação ou ImageIO deve bloquear a main actor.
- Não habilite login, envie telemetria nem adicione contas ou anúncios automaticamente.
- Não faça commits, push ou PR sem solicitação explícita. Não inclua Co-Authored-By.
- Contexto local persistente pode ficar em `.Codex/rules/`, excluído do Git.
