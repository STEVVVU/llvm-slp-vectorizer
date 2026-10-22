"""Curate existing hosted native receipts, including matched old/new assembly."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path, default=Path('docs/evidence/native-metrics.json'))
    args = parser.parse_args()
    raw = json.loads((args.input / 'result.json').read_text())
    rows = list(csv.DictReader((args.input / 'samples.csv').open()))
    if len(rows) != 8 * 3 * 5 * 7 or len(raw['runtime_ns_per_element']) != 8 * 3 * 5:
        raise ValueError('Incomplete frozen matrix')
    if any(row['finished'] != '8' or row['failed'] != '0' or float(row['ns_per_element']) <= 0 for row in rows):
        raise ValueError('Failed or incomplete work')
    assembly = {}
    hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in args.input.iterdir() if path.is_file()}
    sides = ['scalar', 'before', 'bounded', 'greedy', 'upstream']
    for kernel, _, _ in raw['workloads']:
        bodies = {}
        for side in sides:
            text = (args.input / (side + '.s')).read_text()
            match = re.search(r'^' + kernel + r':.*?(?=^\s*\.size\s+' + kernel + r',)', text, re.M | re.S)
            if match is None:
                raise ValueError('Missing assembly body')
            bodies[side] = match[0]
        assembly[kernel] = {'scalar_and_bounded_body_identical': bodies['scalar'] == bodies['bounded'], 'before_and_bounded_body_identical': bodies['before'] == bodies['bounded'], 'per_side': {side: {'movd': len(re.findall(r'\bmovd\b', body)), 'punpck': len(re.findall(r'\bpunpck\w*', body)), 'body_sha256': hashlib.sha256(body.encode()).hexdigest()} for side, body in bodies.items()}}
    comparisons = []
    for kernel, _, _ in raw['workloads']:
        for size in raw['sizes']:
            for side in sides:
                key = f'{kernel}/{size}/{side}.so'
                actual = [float(row['ns_per_element']) for row in rows if row['kernel'] == kernel and int(row['elements']) == size and row['side'] == side + '.so']
                indices = {int(row['repeat']) for row in rows if row['kernel'] == kernel and int(row['elements']) == size and row['side'] == side + '.so'}
                if len(actual) != 7 or indices != set(range(7)) or actual != raw['runtime_ns_per_element'][key]['samples']:
                    raise ValueError('Raw CSV and summary disagree')
            old = raw['runtime_ns_per_element'][f'{kernel}/{size}/before.so']
            new = raw['runtime_ns_per_element'][f'{kernel}/{size}/bounded.so']
            verdict = 'overlap'
            if new['range'][0] > old['range'][1]:
                verdict = 'new slower; nonoverlapping full ranges'
            elif new['range'][1] < old['range'][0]:
                verdict = 'new faster; nonoverlapping full ranges'
            comparisons.append({'kernel': kernel, 'elements': size, 'old_ns_per_element': old, 'new_ns_per_element': new, 'range_comparison': verdict})
    result = {'run_url': 'https://github.com/STEVVVU/llvm-slp-vectorizer/actions/runs/39730682620', 'raw_sha256': hashes, 'assembly_review': assembly, 'matched_old_new': comparisons, 'hosted_result': raw}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(args.output)
    for comparison in comparisons:
        if comparison['range_comparison'] != 'overlap':
            print(comparison['kernel'], comparison['elements'], comparison['range_comparison'])


if __name__ == '__main__':
    main()
