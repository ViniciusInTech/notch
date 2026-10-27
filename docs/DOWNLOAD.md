# Baixar o Notch

**[Baixar Notch para macOS (.dmg)](https://github.com/ViniciusInTech/notch/raw/refs/heads/main/installers/Notch.dmg)**

O instalador fica na pasta [`installers`](../installers) do próprio repositório.
O botão inicia o download direto do GitHub, sem App Store e sem passar por
uma página de versões.

O instalador atual é para Apple Silicon e macOS 14 ou superior.
Depois de baixar, siga o [guia de instalação e configuração](SETUP.md).

## Conferir o arquivo

O checksum SHA-256 está em [`installers/SHA256SUMS.txt`](../installers/SHA256SUMS.txt).
Para calcular o valor do arquivo baixado, use no Terminal:

```sh
shasum -a 256 ~/Downloads/Notch.dmg
```

Compare o resultado com o valor listado no repositório.

## Atualizações do instalador

O arquivo público mantém o nome `installers/Notch.dmg`, para o endereço de download
continuar o mesmo. O script `./scripts/package-dmg.sh` gera o pacote em `dist`,
atualiza essa cópia e grava seu checksum. Revise o app e o instalador antes de
disponibilizar uma versão nova.

[Voltar ao projeto](../README.md)
