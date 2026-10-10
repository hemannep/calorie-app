"""Build the checked-in offline food catalog from USDA FNDDS 2021-2023.

Download: https://fdc.nal.usda.gov/download-datasets/
Input: FoodData_Central_survey_food_json_2024-10-31.zip
Usage: python3 tools/generate_food_catalog.py /path/to/archive.zip
"""

import json
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'lib/data/expanded_food_database.dart'
TARGET = 500
PRIORITY = [
    'samosa', 'biryani', 'pho', 'sushi', 'taco', 'injera', 'couscous', 'ramen',
    'dumpling', 'falafel', 'empanada', 'pupusa', 'pad thai', 'fufu', 'plantain',
    'dosa', 'idli', 'vada', 'naan', 'dal', 'kimchi', 'bibimbap', 'wonton', 'bao',
    'burrito', 'quesadilla', 'enchilada', 'arepa', 'tamale', 'ceviche', 'paella',
    'gnocchi', 'tzatziki', 'hummus', 'baklava', 'croissant', 'sauerkraut',
    'lasagna', 'gelato', 'curry', 'kebab', 'pita', 'miso', 'tempura', 'teriyaki',
    'tofu', 'stir-fry', 'fried rice', 'chow mein', 'congee', 'shakshuka',
    'tabbouleh', 'kofta', 'polenta', 'pierogi', 'goulash', 'stroganoff',
    'bratwurst', 'pretzel', 'frittata', 'churro', 'flan', 'tortilla', 'guacamole',
    'nachos', 'fajita', 'chili', 'cornbread', 'barbecue', 'pancake', 'waffle',
    'oatmeal', 'granola', 'sandwich', 'burger', 'pizza', 'pasta', 'spaghetti',
    'macaroni', 'soup', 'stew', 'salad', 'salmon', 'shrimp', 'tuna', 'turkey',
    'beef', 'chicken', 'pork', 'lamb', 'apple', 'banana', 'mango', 'orange',
    'avocado', 'potato', 'carrot', 'spinach', 'broccoli', 'lentil', 'bean',
    'rice', 'quinoa', 'bread', 'yogurt', 'cheese', 'egg', 'milk', 'coffee',
    'tea', 'smoothie', 'cassava', 'okra',
]
EXCLUDE = re.compile(
    r'\b(?:nfs|ns as|infant|baby|toddler|formula|diet|light|imitation|'
    r'reduced fat|fat free|with added|without|not specified|bear|dove|'
    r'groundhog|opossum|squirrel|beaver|raccoon|armadillo|mock chicken|'
    r'thuringer|frescavena)\b', re.I
)
REGIONS = {
    'Asian': ['samosa', 'biryani', 'pho', 'sushi', 'ramen', 'dosa', 'idli', 'vada',
              'naan', 'dal', 'kimchi', 'bibimbap', 'wonton', 'bao', 'pad thai',
              'miso', 'tempura', 'teriyaki', 'tofu', 'stir-fry', 'fried rice',
              'chow mein', 'congee'],
    'African': ['injera', 'fufu', 'plantain', 'couscous', 'cassava', 'okra'],
    'European': ['gnocchi', 'croissant', 'sauerkraut', 'lasagna', 'gelato',
                 'polenta', 'pierogi', 'goulash', 'stroganoff', 'bratwurst',
                 'pretzel', 'frittata', 'paella', 'baklava'],
    'Americas': ['taco', 'empanada', 'pupusa', 'burrito', 'quesadilla',
                 'enchilada', 'arepa', 'tamale', 'ceviche', 'tortilla',
                 'guacamole', 'nachos', 'fajita', 'chili', 'cornbread',
                 'barbecue'],
}
ALIASES = {
    'Samosa': ['samosas'],
    'Biryani with chicken': ['chicken biryani'],
    'Biryani with vegetables': ['vegetable biryani', 'veg biryani'],
    'Soup, pho, with meat': ['meat pho', 'beef pho', 'pho'],
    'Soup, pho, no meat': ['vegetable pho', 'veg pho'],
    'Injera, Ethiopian bread': ['injera'],
    'Bread, naan': ['naan'],
    'Bibimbap, Korean': ['bibimbap'],
    'Couscous, plain, cooked': ['couscous'],
    'Pad Thai, meatless': ['pad thai'],
    'Ramen bowl with chicken': ['chicken ramen'],
    'Ramen bowl, vegetarian': ['vegetarian ramen'],
    'Hummus, plain': ['hummus'],
    'Plantain, cooked, no added fat': ['cooked plantain'],
}


def nutrients(food):
    values = {n.get('nutrient', {}).get('id'): n.get('amount')
              for n in food['foodNutrients']}
    ids = (1008, 1003, 1005, 1004)
    if any(not isinstance(values.get(i), (int, float)) or values[i] < 0
           for i in ids):
        return None
    return [round(values[i], 2) for i in ids]


def quality(food):
    name = food['description']
    return (len(name) + name.count(',') * 5 + name.count('with') * 5
            + name.count(' or ') * 8 + name.count('(') * 8)


def choose_portion(food):
    name = food['description'].lower()
    if name == 'samosa':
        return 75.0, 'piece'
    portions = [(p.get('portionDescription', '').lower(), p.get('gramWeight', 0))
                for p in food.get('foodPortions', [])]
    portions = [(d, float(w)) for d, w in portions if isinstance(w, (int, float))
                and 1 <= w <= 3000]
    patterns = [
        (r'^1 (?:piece|whole|medium|regular|large|small|individual)', 'piece'),
        (r'^1 slice', 'slice'), (r'^1 cup', 'cup'),
        (r'^1 (?:bowl|plate)', 'bowl'), (r'^1 (?:fillet|steak)', 'piece'),
        (r'^1 (?:sandwich|burger|taco|roll|egg|fruit)', 'piece'),
        (r'^1 serving', 'serving'),
    ]
    for pattern, unit in patterns:
        matches = [(d, w) for d, w in portions if re.search(pattern, d)]
        if matches:
            # Prefer a typical medium/regular item over large or small.
            matches.sort(key=lambda x: ('medium' not in x[0] and 'regular' not in x[0],
                                        'large' in x[0], 'small' in x[0]))
            return matches[0][1], unit
    unspecified = [w for d, w in portions if d == 'quantity not specified']
    if unspecified:
        return unspecified[0], 'serving'
    return (portions[0][1], 'serving') if portions else (100.0, 'serving')


def category(food):
    name = food['description'].lower()
    for region, terms in REGIONS.items():
        if any(re.search(r'\b' + re.escape(term) + r'\b', name) for term in terms):
            return region
    native = food.get('wweiaFoodCategory', {}).get('wweiaFoodCategoryDescription', '').lower()
    if any(t in native for t in ('coffee', 'tea', 'milk', 'juice', 'drink', 'smoothie')):
        return 'Drinks'
    if any(t in native for t in ('fruit', 'nut', 'cookie', 'candy', 'snack', 'chip')):
        return 'Snacks'
    if any(t in native for t in ('oatmeal', 'cereal', 'egg', 'pancake', 'waffle')):
        return 'Breakfast'
    if any(t in native for t in ('rice', 'bread', 'vegetable', 'bean', 'cheese')):
        return 'Basics'
    return 'Regional'


def aliases(food):
    name = food['description']
    clean = re.sub(r'[^a-z0-9 ]+', ' ', name.lower())
    clean = re.sub(r'\s+', ' ', clean).strip()
    results = [clean]
    results.extend(ALIASES.get(name, []))
    if ', ' in name:
        head, detail = name.lower().split(', ', 1)
        if re.fullmatch(r'[a-z][a-z -]{1,24}', detail):
            results.append(f'{detail} {head}')
    if len(clean.split()) == 1 and len(clean) > 2:
        results.append(clean[:-1] + 'ies' if clean.endswith('y') else clean + 's')
    if choose_portion(food)[1] in ('piece', 'slice', 'egg'):
        for phrase in list(results[1:]):
            words = phrase.split()
            if len(words) > 1 and words[-1].isalpha():
                last = words[-1]
                plural = last[:-1] + 'ies' if last.endswith('y') else last + 's'
                results.append(' '.join([*words[:-1], plural]))
    return list(dict.fromkeys(results))


def dart_string(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    archive = Path(sys.argv[1])
    with zipfile.ZipFile(archive) as z:
        records = json.loads(z.read('surveyDownload.json'))['SurveyFoods']
    eligible = [f for f in records if nutrients(f) is not None
                and len(f['description']) <= 76
                and not EXCLUDE.search(f['description'])
                and not EXCLUDE.search(f.get('wweiaFoodCategory', {}).get(
                    'wweiaFoodCategoryDescription', ''))
                and not re.search(r'liquor|wine|beer|cocktail|hard cider|not included',
                                  f.get('wweiaFoodCategory', {}).get(
                                      'wweiaFoodCategoryDescription', ''), re.I)]
    selected = []
    selected_ids = set()

    def add(food):
        if food['fdcId'] not in selected_ids:
            selected.append(food)
            selected_ids.add(food['fdcId'])

    for term in PRIORITY:
        matches = [f for f in eligible if re.search(r'\b' + re.escape(term)
                   + r'\b', f['description'], re.I)]
        matches.sort(key=lambda f: (
                                    bool(re.search(r'\b(?:sauce|shell|dip|topping)\b',
                                                   f['description'], re.I)),
                                    not f['description'].lower().startswith(term),
                                    quality(f)))
        for food in matches[:3 if term in ('sushi', 'taco', 'biryani', 'ramen') else 2]:
            add(food)
    buckets = {}
    for food in eligible:
        key = food.get('wweiaFoodCategory', {}).get('wweiaFoodCategoryDescription', '')
        buckets.setdefault(key, []).append(food)
    for bucket in buckets.values():
        bucket.sort(key=quality)
    category_counts = Counter(f.get('wweiaFoodCategory', {}).get(
        'wweiaFoodCategoryDescription', '') for f in selected)
    while len(selected) < TARGET:
        progressed = False
        for key, bucket in sorted(buckets.items(), key=lambda kv: (category_counts[kv[0]], kv[0])):
            if category_counts[key] >= 9:
                continue
            candidate = next((f for f in bucket if f['fdcId'] not in selected_ids), None)
            if candidate is None:
                continue
            add(candidate)
            category_counts[key] += 1
            progressed = True
            if len(selected) == TARGET:
                break
        if not progressed:
            raise RuntimeError(f'Only {len(selected)} eligible foods')
    lines = [
        "import 'models.dart';",
        '',
        '// Generated from USDA FoodData Central FNDDS 2021–2023 (October 2024).',
        '// Nutrition values are per 100 g; serving weights are approximate.',
        '// Rebuild with: python3 tools/generate_food_catalog.py <USDA archive.zip>',
        'const expandedFoods = <Food>[',
    ]
    for food in selected:
        fdc_id = food['fdcId']
        n = nutrients(food)
        serving, unit = choose_portion(food)
        lines.extend([
            '  Food(',
            f"    id: 'fndds-{fdc_id}',",
            f"    name: {dart_string(food['description'])},",
            '    aliases: [' + ', '.join(map(dart_string, aliases(food))) + '],',
            f'    per100g: Nutrients({n[0]}, {n[1]}, {n[2]}, {n[3]}),',
            f'    servingGrams: {serving},',
            f"    unit: '{unit}',",
            "    source: 'USDA FoodData Central · FNDDS 2021–2023',",
            f"    sourceUrl: 'https://fdc.nal.usda.gov/food-details/{fdc_id}/nutrients',",
            f"    category: '{category(food)}',",
            '  ),',
        ])
    lines.append('];')
    OUT.write_text('\n'.join(lines) + '\n')
    print(f'Wrote {len(selected)} USDA foods to {OUT}')
    print('Categories:', dict(Counter(category(f) for f in selected)))
    print('Sample:', [f['description'] for f in selected[:35]])


if __name__ == '__main__':
    main()
