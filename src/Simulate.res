type url

@new external makeURL: (string, 'a) => url = "URL"

@module("fs")
external writeFile: (url, string, @as(json`{"encoding": "utf8"}`) _) => unit = "writeFileSync"
@module("csv-stringify/lib/sync.js") external stringifyCSV: (. array<'a>) => string = "default"

// new URL('./foo.txt', import.meta.url)

type deck = array<Card.t>

type result = {
  idx: int,
  pocketCards: Scoring.pocketCards,
  hand: Scoring.hand,
  score: Scoring.score,
}

let simulations = 1_000_000

let genDeck = (): deck => {
  Belt.Array.makeBy(52, i => {
    Card.suite: Card.suiteOfInt(i / 13),
    rank: Card.rankOfInt(mod(i, 13) + 1),
  })
}

let classify = ({Scoring.p1: p1, p2}) => {
  open Card

  @warning("-8")
  let [card1, card2] = [p1, p2]->Belt.SortArray.stableSortBy(Scoring.compareCards)
  if card1.rank == card2.rank {
    let rankString = card1.rank->stringOfRank
    `${rankString}${rankString}`
  } else if card1.suite == card2.suite {
    `${card1.rank->stringOfRank}${card2.rank->stringOfRank}s`
  } else {
    `${card1.rank->stringOfRank}${card2.rank->stringOfRank}o`
  }
}

let playGame = playerCount => {
  open Belt.Array
  let d = genDeck()->shuffle
  let hands = makeBy(playerCount, i => {
    {Scoring.p1: d->getUnsafe(i), p2: d->getUnsafe(playerCount + i)}
  })
  let board = {
    Scoring.flop1: d->getUnsafe(playerCount * 2 + 1),
    flop2: d->getUnsafe(playerCount * 2 + 2),
    flop3: d->getUnsafe(playerCount * 2 + 3),
    turn: Some(d->getUnsafe(playerCount * 2 + 5)),
    river: Some(d->getUnsafe(playerCount * 2 + 7)),
  }

  let make = Scoring.make(board)
  let compare = Scoring.compare(board)

  let results =
    hands
    ->mapWithIndex((idx, pocketCards) => {
      let (score, hand) = make(pocketCards)
      {idx: idx, hand: hand, score: score, pocketCards: pocketCards}
    })
    ->Belt.SortArray.stableSortBy(({pocketCards: a}, {pocketCards: b}) => compare(a, b))

  let first = results->getUnsafe(0)

  let (winners, losers) =
    results->partition(({pocketCards}) => compare(first.pocketCards, pocketCards) === 0)
  (winners, losers, board)
}

let run = () => {
  open Belt.Array
  let playerCount = 9
  make(simulations, ())
  ->reduce(Js.Dict.empty(), (acc, _) => {
    let (winners, losers, _) = playGame(playerCount)

    winners->forEach(({pocketCards}) => {
      let classification = pocketCards->classify
      acc->Js.Dict.set(
        classification,
        switch acc->Js.Dict.get(classification) {
        | None => (1, 0)
        | Some((wins, loses)) => (wins + 1, loses)
        },
      )
    })

    losers->forEach(({pocketCards}) => {
      let classification = pocketCards->classify
      acc->Js.Dict.set(
        classification,
        switch acc->Js.Dict.get(classification) {
        | None => (0, 1)
        | Some((wins, loses)) => (wins, loses + 1)
        },
      )
    })

    acc
  })
  ->Js.Dict.entries
  ->reduce([], (acc: array<(string, float)>, (key, (wins, loses))) => {
    acc->concat([(key, float_of_int(wins) /. float_of_int(wins + loses))])
  })
  ->stringifyCSV(. _)
  ->writeFile(
    makeURL(
      `../data/odds_${playerCount->string_of_int}_handed.csv`,
      @warning("-103") %raw(`import.meta.url`),
    ),
    _,
  )
}
