# Publicar uma versão assinada

Sem assinatura Developer ID e notarização, o macOS mostra “A Apple não pôde
verificar se o Notch está livre de malware” e exige liberação manual nos ajustes.
Com elas, aparece só a confirmação padrão de app baixado da Internet.

[Voltar ao projeto](../README.md)

## Pré-requisitos (uma vez)

1. Inscrição no [Apple Developer Program](https://developer.apple.com/programs/) (anual, pago).
2. Certificado **Developer ID Application** criado no Xcode
   (Settings → Accounts → Manage Certificates) ou no portal de desenvolvedor,
   instalado no Keychain. Confira com:

   ```sh
   security find-identity -v -p codesigning
   ```

3. Uma senha específica de app em [account.apple.com](https://account.apple.com)
   e o perfil do notarytool guardado no Keychain:

   ```sh
   xcrun notarytool store-credentials notch-notary \
       --apple-id "voce@exemplo.com" --team-id "TEAMID" --password "senha-de-app"
   ```

   Credenciais ficam só no Keychain; nada é gravado no repositório.

## Gerar o instalador

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Seu Nome (TEAMID)" \
NOTARY_PROFILE=notch-notary \
./scripts/package-dmg.sh
```

O script:

1. assina o app com hardened runtime, entitlements e timestamp seguro;
2. gera o DMG com fundo e ícones posicionados;
3. assina o DMG, envia ao `notarytool` e espera o resultado;
4. grampeia o ticket no DMG (`stapler`), para a verificação funcionar offline;
5. confere com `spctl` e atualiza `installers/Notch.dmg` e o checksum.

Se a notarização falhar, veja o motivo com:

```sh
xcrun notarytool log <id-da-submissão> --keychain-profile notch-notary
```

Sem as variáveis, o script gera um DMG com assinatura ad hoc e avisa que ele não
foi notarizado. Não publique esse arquivo como versão final.

Na primeira geração, o macOS pode pedir para o Terminal controlar o Finder:
é ele quem grava a posição dos ícones e o fundo da janela.
