#!/usr/bin/env python3

"""
A simple script to take a CSV with three defined columns (SampleID, R1, R2) and a fourth 
treatment column given as an option, and generates sample subsets for each treatment.  

NOTE: this doesn't sanity check the columns yet
"""

import argparse
import pandas as pd
import sys

def main():
    args = get_arguments()
    # read CSV into a pandas DataFrame (we could maybe use standard python csv)
    df = pd.read_csv(args.csv)
    colnames = df.columns if args.colnames == None else args.colnames
    
    # group by treatment
    groups = df.groupby(args.treatment, as_index=False)
    	
    for rep in range(1, args.number + 1, 1):
        # subset a sample from each group
        subsample = groups.apply(lambda gp: gp.sample(n = args.sample)).reset_index()
        subsample.to_csv('sample' + str(rep) + '.csv', index_label='RowID', columns=colnames)

def get_arguments():
    parser = argparse.ArgumentParser(description='')
    parser.add_argument('-c', '--csv', required=True,
                        help='Input CSV to be subsampled')
    parser.add_argument('-o', '--output', required=True,
                        help='Output prefix for subsampled CSV files')
    parser.add_argument('-t', '--treatment', nargs='+', type=str, default=['Treatment'],
                        help='Column name(s) for treatment')
    parser.add_argument('-n', '--number', type=int, default=1,
                        help='Number of times to run sampling.')
    parser.add_argument('-s', '--sample', type=int, default=5,
                        help='Sample size to extract.  NOTE: we do not sanity check this yet')
    parser.add_argument('--colnames', nargs='+', type=str, 
                        help='Column name(s) for output (if not set, print all)')
                        
    if len(sys.argv) == 1:
        parser.print_help(file=sys.stderr)
        sys.exit(1)

    args = parser.parse_args()

    return args

if __name__ == '__main__':
    main()
