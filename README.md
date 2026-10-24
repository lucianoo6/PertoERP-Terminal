<p align="center">
  <img src="assets/brand/icon.png" alt="Perto Terminal" width="96">
</p>

<h1 align="center">Perto Terminal</h1>

<p align="center">
  <strong>A venda é feita no PertoERP e o cupom sai na sua impressora térmica, sozinho, na hora.</strong><br>
  Grátis para quem usa o <a href="https://pertoerp.com.br">PertoERP</a> · Windows e Linux
</p>

<p align="center">
  <a href="https://pertoerp.com.br/terminal"><strong>⬇ Baixar o Perto Terminal</strong></a>
</p>

---

## O que é

O PertoERP funciona no navegador, do computador, do tablet ou do celular. Só que o navegador não consegue mandar o cupom direto para a impressora térmica do balcão. É aí que entra o **Perto Terminal**.

Ele é um programa pequeno que você instala **uma vez** no computador onde a impressora está ligada. Depois disso, ele fica quietinho ao lado do relógio do Windows e, toda vez que uma venda é finalizada no PertoERP, em qualquer aparelho da loja, imprime o cupom na hora.

- 🧾 **Imprime o cupom fiscal (DANFE NFC-e) e o comprovante de venda**, com QR Code e acentos certinhos.
- ⚡ **Na hora:** a impressão chega em menos de um segundo depois da venda.
- 📱 **Venda de qualquer lugar:** quem vende no tablet ou no celular imprime na térmica do caixa.
- 💵 **Abre a gaveta de dinheiro** sozinho quando a venda é paga em dinheiro (opcional).
- ✂️ **Corta o papel** no fim de cada cupom, se a impressora tiver guilhotina.
- 🔁 **Não perde impressão:** se a internet cair, ele imprime tudo o que ficou pendente assim que ela voltar.
- 🖨️ **Caixa, cozinha, bar…:** cada impressora escolhe o seu setor numa lista que vem do PertoERP. Um computador pode ter várias térmicas (ex.: cozinha e bar no mesmo PC), ou cada setor com o seu computador.

## Impressoras compatíveis

Funciona com as térmicas mais usadas no comércio: **Elgin** (i7, i8, i9), **Epson** (TM-T20, TM-T88), **Bematech** (MP-4200), **Daruma**, **Tanca**, **Knup**, **Sweda**, **Control iD** e outras que usam o padrão ESC/POS.

- Ligada por **USB**, pela **rede** (cabo ou Wi-Fi, com IP) ou por **porta serial**.
- Bobina de **80 mm** ou **58 mm**.

## Como configurar (5 minutos)

### 1. Cadastre o terminal no PertoERP

No PertoERP, vá em **Configurações › Terminais de impressão** e clique em **Novo terminal**. Dê um nome (ex.: *Caixa 1*) e salve. Vai aparecer um **token**: copie, porque é ele que liga este computador à sua loja.

### 2. Baixe e abra o Perto Terminal

Baixe em **[pertoerp.com.br/terminal](https://pertoerp.com.br/terminal)**, clique com o botão direito no arquivo e escolha **Extrair tudo**. Guarde a pasta num lugar fixo (ex.: *Documentos*) e abra o **PertoTerminal**.

> Na primeira vez, o Windows pode mostrar um aviso azul ("O Windows protegeu o computador"). Clique em **Mais informações** e em **Executar assim mesmo**.

### 3. Cole o token e escolha a impressora

Na janela do Perto Terminal:

1. Em **Endereço do PertoERP**, deixe `https://pertoerp.com.br`.
2. Cole o **token** e clique em **Testar conexão**. Deve aparecer o nome do terminal que você cadastrou.
3. Escolha a **impressora térmica** e a **largura da bobina** (80 mm ou 58 mm).
4. Clique em **Imprimir página de teste**.
5. Se a página saiu certa, clique em **Salvar e conectar**. Pronto!

### 4. Deixe abrindo junto com o computador

Em **Mais opções**, ligue **Abrir junto com o Windows**. Assim, mesmo depois de reiniciar o computador, o terminal já está pronto quando a loja abrir.

## No dia a dia

O Perto Terminal fica no **ícone verde ao lado do relógio**. Pode fechar ou minimizar a janela que ele continua imprimindo.

| Ícone | O que significa |
| --- | --- |
| 🟢 Verde | Tudo certo, pronto para imprimir |
| 🟠 Laranja | Imprimindo, mas a conexão rápida está se reconectando |
| 🔴 Vermelho | Problema: sem internet, impressora desligada ou sem papel. Abra a janela para ver o motivo |
| ⚪ Cinza | Falta configurar |

> Não está vendo o ícone? No Windows 11 ele pode estar escondido na **setinha ^** da barra de tarefas. Arraste-o para fora para deixar sempre à vista.

## Dúvidas comuns

**Os acentos saíram trocados (ex.: "Ã§" no lugar de "ç").**
Em **Tabela de acentos**, troque para outra opção e imprima a página de teste de novo. Para a maioria das impressoras, a **CP850** é a certa.

**A impressora não imprime e aparece "não aceitou dados diretos".**
Nas **Impressoras do Windows**, abra **Propriedades da impressora › Avançado › Processador de impressão** e escolha **winprint** com o tipo **RAW**. Ou instale a impressora com o driver **Generic / Text Only**.

**O cupom saiu cortado ou espremido.**
Confira a **largura da bobina**: 80 mm para a bobina larga e 58 mm para a estreita.

**Preciso de um terminal por computador?**
Sim: cada computador com impressora térmica precisa do Perto Terminal instalado e do seu próprio token. Quem só vende (tablet, celular, outro computador) não precisa instalar nada.

**Trocou de computador?**
Instale o Perto Terminal no novo computador e use o mesmo token, ou gere um novo no PertoERP e desative o antigo.

## Linux

Baixe o arquivo **linux** em [pertoerp.com.br/terminal](https://pertoerp.com.br/terminal), extraia e abra o `perto-terminal`. A impressora precisa estar instalada no sistema (CUPS). Para o ícone aparecer ao lado do relógio, o pacote `libayatana-appindicator3-1` precisa estar instalado.

## Precisa de ajuda?

Fale com o suporte pelo WhatsApp, no botão **Suporte no WhatsApp** dentro do PertoERP (no menu do seu usuário).

---

<details>
<summary>Para desenvolvedores</summary>

Feito em Flutter (Windows e Linux). Cada tag `vX.Y.Z` enviada ao GitHub roda os testes, compila os dois sistemas e publica o Release, que aparece sozinho na página de downloads do PertoERP.

```bash
flutter test
flutter run -d windows
git tag -a v1.1.0 -m "Novo: aviso quando sai versão nova do terminal."   # a mensagem vira as novidades no site`ngit push origin v1.1.0
```

Os testes em `test/ticket_test.dart` comparam byte a byte com os cupons gerados pela primeira versão do terminal, em `test/fixtures`.

</details>
