#!/usr/bin/env python3
"""Reproduce descriptive statistics. Seats and repeated rounds are not independent trials."""
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median

ROOT = Path(__file__).resolve().parent
POLICIES = ['economy', 'expansion', 'evolution', 'tempo']

def read(path):
    return json.loads(path.read_text())

def summarize(folder):
    games = read(folder / 'tournaments.json')
    catalog = read(folder / 'catalog.json')
    contexts = read(folder / 'contexts.json')
    assert len(catalog['units']) == 84 and len(contexts) == 396
    assert len({(g['seed'], g['strategy_offset']) for g in games}) == len(games) == 16
    policy = defaultdict(list)
    per_game = []
    for game in games:
        assert sorted(game['placements']) == list(range(1, 10))
        members = {s['seat']: s['strategy'] for s in game['samples'] if s['round'] == 1}
        for seat, place in enumerate(game['placements']):
            policy[members[seat]].append(place)
        per_game.append({name:mean(game['placements'][seat] for seat in range(9) if members[seat] == i)
                         for i, name in enumerate(POLICIES)})
    forms = defaultdict(lambda: Counter(wins=0, draws=0, trials=0))
    for row in contexts:
        assert row['trials'] == 4 and 0 <= row['wins'] + row['draws'] <= 4
        for family, wins in [(row['a'],row['wins']), (row['b'],4-row['wins']-row['draws'])]:
            score = forms[family, row['rank']]
            score.update(wins=wins, draws=row['draws'], trials=4)
    family_rows = []
    for family in range(28):
        row = {'family':family, 'name':catalog['units'][family*3]['name']}
        row['context_scores'] = {str(rank+1):dict(forms[family,rank], score=(forms[family,rank]['wins']+.5*forms[family,rank]['draws'])/forms[family,rank]['trials']) for rank in [1,2]}
        row['games_deployed'] = sum(any(family in s['families'] for s in g['samples']) for g in games)
        row['late_snapshots'] = sum(s['families'].count(family) for g in games for s in g['samples'] if s['round'] >= 17)
        family_rows.append(row)
    stars = defaultdict(Counter)
    for row in read(folder/'stars.json'):
        stars[row['kind']].update({k:row[k] for k in ['wins','draws','trials','timeouts']})
    # Only the four holdout games have duration records in both builds.
    enc = [e for g in games[12:] for e in g['encounters']]
    times = sorted(e['seconds'] for e in enc)
    return {
        'games':len(games), 'unique_seeds':len({g['seed'] for g in games}),
        'policies':{name:{'seats':len(policy[i]),'mean_place':mean(policy[i]),'wins':policy[i].count(1),'top4':sum(v<=4 for v in policy[i])} for i,name in enumerate(POLICIES)},
        'per_game_means':per_game, 'families':family_rows,
        'contexts':{'fights':sum(r['trials'] for r in contexts),'timeouts':sum(r['timeouts'] for r in contexts),'mean_seconds':mean(r['seconds'] for r in contexts)},
        'stars':dict(stars),
        'holdout_boards':{'count':len(enc),'reasons':dict(Counter(e['reason'] for e in enc)), 'median_seconds':median(times),'p90_seconds':times[math.ceil(.9*len(times))-1]},
        'rounds':{'mean':mean(g['rounds'] for g in games),'min':min(g['rounds'] for g in games),'max':max(g['rounds'] for g in games)},
    }

def acquisition(catalog):
    counts = Counter(u['cost'] for u in catalog['units'] if u['rank']==0)
    rows=[]
    for level, odds in catalog['odds'].items():
        for tier, weight in enumerate(odds,1):
            if not weight:continue
            p=weight/100/counts[tier]
            # Each paid shop has five independent slots. Account for surplus
            # copies in the final shop, rather than dividing expected slots by five.
            shops=[0.0]
            chance=[math.comb(5,k)*p**k*(1-p)**(5-k) for k in range(6)]
            for missing in range(1,9):
                shops.append((1+sum(chance[k]*shops[max(0,missing-k)] for k in range(1,6)))/(1-chance[0]))
            probabilities={str(rolls):{str(needed):1-sum(math.comb(5*rolls,k)*p**k*(1-p)**(5*rolls-k) for k in range(needed)) for needed in [2,8]} for rolls in [5,10,20]}
            rows.append({'level':int(level),'tier':tier,'species':counts[tier],'slot_chance':p,'expected_reroll_gold_for_eight_more':2*shops[8],'probabilities':probabilities})
    return rows

before_games=read(ROOT/'before/tournaments.json');final_games=read(ROOT/'final/tournaments.json')
assert [(g['seed'],g['strategy_offset']) for g in before_games] == [(g['seed'],g['strategy_offset']) for g in final_games]
summary={name:summarize(ROOT/name) for name in ['before','intermediate-a','final']}
summary['acquisition']=acquisition(read(ROOT/'final/catalog.json'))
(ROOT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
for name in ['before','final']:
    print(name,summary[name]['policies'])
print('Fixed-level tier-1, level-4 eight-copy search:',next(r for r in summary['acquisition'] if r['level']==4 and r['tier']==1))
