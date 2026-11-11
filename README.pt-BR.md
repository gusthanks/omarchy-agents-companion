# Agents Pet

**Kian**: um bichinho plano que mora na barra do [Omarchy](https://omarchy.org) e no painel
Agents. Ele faz companhia enquanto você trabalha, segue o cursor pela tela, reage aos
limites dos seus agentes de IA (Claude, Codex, Antigravity, …) e dá dicas de uso com calma.
Você pode remodelá-lo do jeito que quiser.

🇺🇸 [Read in English](README.md)

<p align="center"><img src="docs/demo.gif" width="420" alt="O bichinho seguindo o cursor, recebendo carinho, uma festa, levando um susto e ficando tonto, cochilando e depois experimentando outros visuais"></p>

> Feito sobre o painel **Agents** padrão do Omarchy (MIT). Tudo o que o painel padrão faz
> (limites, ritmo, saldos, várias contas) continua aqui. O bichinho fica por cima.

## O que você ganha

- **Um bichinho na barra**: o ícone da barra é o próprio bichinho, piscando de leve. O
  tamanho acompanha a altura da barra (Pequeno / Médio / Grande por cima disso, separado
  do bichinho do painel).
- **Um bichinho vivo no painel**: ele respira, pisca e, com o painel aberto, segue o cursor
  em qualquer lugar da tela. Clique nele para fazer carinho: ele se espreme, sorri e solta
  um coração (alguns carinhos seguidos e ele pula; carinho demais deixa ele tonto). Deixe o
  mouse parado um tempo e ele boceja e cochila (mais cedo tarde da noite); mexa o mouse ou
  faça carinho e ele acorda se espreguiçando.
- **Pequenas reações**: ele pensa enquanto o uso atualiza, se assusta quando o cursor vem
  correndo, inclina a cabeça quando o cursor para perto, pisca um olá, solta um "ufa" quando
  uma assinatura bate no teto e um suspiro quando um limite deixa de estar perto. De vez em
  quando espirra ou boceja. Na barra ele só mostra poses paradas, para ficar leve.
- **Humores pelos limites**: preocupado (sobrancelhas levantadas, um "!") quando um limite
  está perto, cansado ("z") quando todas as assinaturas estouraram, e uma festinha de
  confete quando uma volta. A cor dele nunca muda; as barras de limite continuam ficando
  vermelhas como sempre.
- **Chapéus de época**: gorro de Papai Noel em 24–25/12 e chapéu de festa em 31/12 e 1/1.
- **Uma linha de dica tranquila** sob o nome do bichinho: primeiro as informações ao vivo
  (um limite perto ou no teto com o horário de renovação, uma assinatura mais folgada para
  trocar, tokens hoje e por sessão, um lembrete tarde da noite), depois dicas gerais para
  trabalhar com agentes.
- **Pet Studio**: forma, rosto, extras, cor, personalidade e bichinhos salvos, com backup
  e exportação em PNG (veja [Uso](#uso)).

<p align="center"><img src="docs/sheet.png" width="520" alt="Corpos, olhos, extras de cabeça, acessórios, humores e reações"></p>

O painel segue o idioma do Omarchy: os textos do painel padrão vêm nas 50 línguas do
Omarchy, e os do bichinho em inglês e português do Brasil.

## Instalação

```bash
omarchy plugin add https://github.com/gusthanks/omarchy-agents-pet.git --enable
```

Atualize com `omarchy plugin update gusthx.agents-pet` e desinstale com
`omarchy plugin remove gusthx.agents-pet`. Remover o plugin mantém seu bichinho em
`~/.config/omarchy/agents-pet.json`; apague esse arquivo também se quiser.

> [!NOTE]
> O Agents Pet substitui o widget **Agents** padrão da barra. Deixe só um dos dois na barra.

**Dica:** uma barra um pouco mais alta combina com o bichinho. Coloque isto em
`~/.config/omarchy/shell.toml` (vale para todos os temas):

```toml
[bar]
size-horizontal = 30
size-vertical = 32
```

## Uso

Clique no bichinho na barra para abrir o painel. A dica sob o nome aparece inteira, em
algumas linhas; passar o mouse por cima pausa a troca, e o botão › pula para a próxima.
Alertas de limite aparecem em vermelho. Clique no bichinho para fazer carinho.

**Pet Studio**: clique na engrenagem no topo do painel. Em cima ficam um palco com o
bichinho, um botão de sorteio e o nome; embaixo, cinco abas, e Desfazer / Restaurar /
Pronto no rodapé:

- **Forma**: corpo (bolha, orbe, quadradinho, gota, fantasma, nuvem, ovo, mochi, feijão),
  estilo (sólido ou contorno) e o tamanho do bichinho na barra e no painel (Pequeno /
  Médio / Grande, cada um)
- **Rosto**: olhos (cápsula, pontinhos, esbugalhados, pixel, sonolentos, estrela,
  brilhante, ciclope, coração), boca (nenhuma, sorriso, surpresa, gatinho, reta, presinha,
  língua, sorrisão, sorriso de lado), o tamanho de cada um (Bem pequeno a Bem grande),
  bochechas coradas e a **personalidade**: Animado (todas
  as reações e pequenas manias), Calmo (reage a você, sem manias à toa) ou Quieto
  (só poses, sem reações animadas); uma linha **Testar** toca Piscar, Susto, Tontura,
  Bocejo e Festa no palco
- **Extras**: cabeça (antena, folha, orelhas de gato, chifres, auréola, topete, orelhas de
  coelho, chifre de unicórnio) e acessório (óculos, cartola, gorro, laço, flor, fone de
  ouvido, coroa, cachecol, gravata-borboleta)
- **Cor**: as cores do tema atual (acompanham a troca de tema), ou qualquer cor do seletor
  ou de um código hex; uma linha **Recentes** guarda as últimas 8 cores personalizadas
  (continuam lá depois de Desfazer e Restaurar, e vão junto no backup)
- **Salvos**: guarde os bichinhos que criar (até 24) e use de novo com um clique; copie /
  cole um bichinho como um código JSON curto; **Backup** grava o bichinho
  atual, os salvos, os tamanhos, a personalidade e as cores recentes em `agents-pet-backup.json` na sua pasta
  Documentos (a do XDG, normalmente `~/Documents`, ou `~/` se não houver) e **Restaurar**
  lê de volta com as mesmas verificações de um código colado; **Salvar PNG** salva o
  bichinho como imagem transparente de 1024 px `agents-pet-<nome>.png` na sua pasta
  Imagens (XDG, normalmente `~/Pictures`)

Apontar para uma opção experimenta ela no palco; um clique confirma. O sorteio gera um
visual aleatório, Restaurar (no rodapé) volta ao padrão, e Desfazer devolve o último sorteio,
redefinição, bichinho vestido, removido, colado ou restaurado. As mudanças valem na hora e
ficam salvas em `~/.config/omarchy/agents-pet.json`.

<p align="center"><img src="docs/editor.png" width="260" alt="Ajustes do bichinho, aba Rosto: olhos e bocas, bochechas, personalidade e a linha Testar"></p>
<p align="center"><img src="docs/editor-shape.png" width="200" alt="Aba Forma">&nbsp;<img src="docs/editor-extras.png" width="200" alt="Aba Extras">&nbsp;<img src="docs/editor-color.png" width="200" alt="Aba Cor">&nbsp;<img src="docs/editor-saved.png" width="200" alt="Aba Salvos: bichinhos salvos, códigos, backup e PNG"></p>

As imagens mostram a interface em inglês; com o Omarchy em português ela aparece traduzida.

**Teclado** (no Pet Studio):

| Tecla | Ação |
|---|---|
| Setas / `h` `j` `k` `l` | Andar entre as opções |
| `Enter` | Escolher |
| `1`–`5`, `[` `]` | Trocar de aba |
| `r` | Visual aleatório |
| `u`, `Ctrl+Z` | Desfazer |
| `s` | Salvar o bichinho |
| `c` / `v` | Copiar / colar um código |
| `e` | Editar o nome |
| `x`, `Delete`, `Backspace` | Remover um bichinho salvo |
| `Esc` | Voltar um nível (seletor, depois o editor, depois o painel) |

**IPC** (`omarchy-shell gusthx.agents-pet <método>`): `open`, `close`, `show`, `hide`,
`toggle`, `refresh`, `nextInsight`, `editPet`, `pat`, `celebrate`, `react <nome>` (pat, hop,
celebrate, yawn, wake, startle, curious, dizzy, wink, sneeze, thinking, oof, sigh).

## Configuração

| Onde | O quê |
|---|---|
| Engrenagem no painel | Visual, nome, tamanho, personalidade e salvos (`~/.config/omarchy/agents-pet.json`) |
| Ajustes do widget / `shell.json` → `companionName` | Nome reserva quando os ajustes não definem um |
| Ajustes do widget / `shell.json` → `refreshIntervalSec`, `sync*` | Igual ao painel Agents padrão |

## Privacidade

O bichinho não faz nenhuma chamada de rede. O que ele usa:

- `~/.config/omarchy/agents-pet.json` (seu bichinho, os salvos, tamanho e personalidade).
- A área de transferência, só quando você aperta **Copiar código** / **Colar código**
  (`wl-copy` / `wl-paste`). O código guarda só o nome e o visual; códigos colados são
  conferidos contra as opções conhecidas antes de usar.
- `agents-pet-backup.json` na pasta Documentos, só quando você aperta **Backup** (grava) ou **Restaurar** (lê). Backups restaurados passam pelas mesmas
  verificações dos códigos colados.
- `agents-pet-<nome>.png` na pasta Imagens, só quando você aperta **Salvar PNG**.

Os números de uso vêm dos coletores padrão do próprio Omarchy (`omarchy-agent-usage-*`),
os mesmos que o painel Agents padrão roda. Eles leem os arquivos de credencial locais de
cada agente (por exemplo `~/.claude/.credentials.json`, `~/.codex/auth.json`) e falam só
com a API do próprio provedor (Anthropic, OpenAI, GitHub, Cursor, Google etc.). Esse código
vem com o Omarchy e não faz parte deste repositório.

## Desenvolvimento

Trabalhe num clone **fora** da pasta do plugin e teste no ambiente isolado, para a barra
que você está usando nunca recarregar no meio do trabalho. Veja o [AGENTS.md](AGENTS.md)
(em inglês).

```bash
git clone https://github.com/gusthanks/omarchy-agents-pet.git ~/Work/omarchy-agents-pet
cd ~/Work/omarchy-agents-pet
dev/run.sh preview      # instância separada do Quickshell com o bichinho e os ajustes
dev/run.sh editor face  # docs/editor-face.png (qualquer aba: shape face extras color saved)
dev/run.sh png          # testa Salvar PNG, backup / restauração e as teclas (pasta temporária)
dev/run.sh gif          # docs/demo.gif (uns 12 s)
dev/run.sh docs         # gera de novo todas as imagens de docs/
dev/run.sh check        # compila todos os tipos, inclusive o Panel.qml, e as bibliotecas de usage/
dev/run.sh test         # testes em Node das contas de uso em usage/
omarchy plugin validate .
git commit -am "..."    # e, quando terminar:
dev/deploy.sh           # avança o plugin instalado até o HEAD
```

As capturas usam o seu próprio bichinho por padrão; use
`PET_FILE=/caminho/agents-pet.json` para renderizar outro.

A raiz do repositório é a pasta do plugin, o formato que o `omarchy plugin add` espera.
Os arquivos estão descritos na seção
[Development do README em inglês](README.md#development).

## Mudanças

Veja o [CHANGELOG.md](CHANGELOG.md) (em inglês).

## Créditos

- Painel Agents padrão (`Main.qml`, `Agent.qml`, `assets/`, o painel e os coletores em que
  este plugin se baseia): o projeto [Omarchy](https://github.com/basecamp/omarchy), MIT,
  Copyright (c) David Heinemeier Hansson.
- Ideia do bichinho paramétrico inspirada no escultor de robôs do app móvel Hermes Agent.
- O ritmo, a prioridade de "use ou perca", os avisos de limite e a leitura dos avisos em
  `usage/` foram portados do [ai-usagebar](https://github.com/akitaonrails/ai-usagebar), MIT,
  Copyright (c) 2026 AkitaOnRails.

## Licença

MIT. Veja a [LICENSE](LICENSE).
