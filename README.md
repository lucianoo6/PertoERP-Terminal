# Perto Terminal

Fica na bandeja do computador do caixa e imprime na térmica os cupons e DANFEs NFC-e enviados pelo [PertoERP](https://pertoerp.com.br).

- Windows (impressora instalada em modo RAW, rede porta 9100 ou porta COM/LPT) e Linux (CUPS em modo bruto, rede ou `/dev/usb/lp0`).
- Recebe as impressões na hora pelo tempo real (Reverb) e, se ele cair, consulta a fila a cada poucos segundos.
- ESC/POS com acentos (CP850, CP860, Windows-1252), QR Code nativo, corte de papel e abertura de gaveta.

## Baixar

As versões ficam em [Releases](../../releases) e na página de downloads do PertoERP.

- **Windows:** descompacte o `.zip` e abra `PertoTerminal.exe`.
- **Linux:** `tar -xzf PertoTerminal-*-linux-x64.tar.gz && ./perto-terminal/perto-terminal`. Precisa de `libayatana-appindicator3-1` para o ícone na bandeja.

## Publicar uma versão

```bash
git tag v1.1.0
git push origin v1.1.0
```

O GitHub Actions roda os testes, compila Windows e Linux e cria o Release com os dois pacotes.

## Desenvolvimento

```bash
flutter test
flutter run -d windows
```

Os testes em `test/ticket_test.dart` comparam byte a byte com os cupons gerados pela primeira versão do terminal (em Go), em `test/fixtures`.
