
import extern
import pandas as pd

num_threads = config['benchmarking_threads']

tools = ['singlem', 'metaphlan', 'motus', 'kracken', 'sourmash']
# tools = ['singlem']

output_prefix = 'output_'
output_dirs = list([output_prefix+tool for tool in tools])
output_dirs_dict = dict(zip(tools, output_dirs))

benchmark_dir = 'benchmarks'

datasets = extern.run('ls ~/m/msingle/mess/115_camisim_ish_benchmarking/simulated_reads/*.1.fq.gz').split()
datasets = [os.path.basename(x).split('.')[0] for x in datasets]
datasets = [datasets[0]]

original_reads_dir = '/home/woodcrob/m/msingle/mess/115_camisim_ish_benchmarking/simulated_reads'
fastq_dir = 'local_reads'
truth_dir = '~/m/msingle/mess/115_camisim_ish_benchmarking/truths'


singlem_git_base_directory = '~/m/msingle/mess/115_camisim_ish_benchmarking/singlem'


##################################################################### reference databases

metapackage = '/home/woodcrob/git/singlem/db/S3.1.0.metapackage_20221209.smpkg.uploaded'
# metapackage = '~/l/git/singlem/db/S3.1.0.metapackage_20221209.smpkg.uploaded'
singlem_metapackage = output_dirs_dict['singlem'] + '/singlem/data/S3.1.0.metapackage_20221209.smpkg'

metaphlan_db_original1 = '~/m/msingle/mess/115_camisim_ish_benchmarking/metaphlan_bowtiedb'
metaphlan_db_local1 = output_dirs_dict['metaphlan'] + '/metaphlan/data/metaphlan_bowtiedb'

motus_db_path_original = '/home/woodcrob/e/motus-v3.0.3/lib/python3.9/site-packages/motus/db_mOTU'
motus_db_path_local = output_dirs_dict['motus'] + '/motus/data/db_mOTU'
motus_gtdb_tsv = '~/m/msingle/mess/115_camisim_ish_benchmarking/motus/mOTUs_3.0.0_GTDB_tax.tsv'

kracken_db = "/home/woodcrob/m/db/struo2/GTDB_release207"
kraken_db_local = output_dirs_dict['kracken'] + "/kraken/data/GTDB_release207"
kracken2_install = '~/bioinfo/kraken2/install/'
bracken_install = '~/bioinfo/Bracken/'

sourmash_db1_original = '/home/woodcrob/m/msingle/mess/105_novelty_testing/gtdb-rs207.taxonomy.sqldb'
sourmash_db2_original = '/home/woodcrob/m/msingle/mess/105_novelty_testing/gtdb-rs207.genomic-reps.dna.k31.zip'
sourmash_db1 = output_dirs_dict['sourmash'] + '/sourmash/data/gtdb-rs207.taxonomy.sqldb'
sourmash_db2 = output_dirs_dict['sourmash'] + '/sourmash/data/gtdb-rs207.genomic-reps.dna.k31.zip'

#####################################################################


rule all:
    input:
        # expand("{output_dir}/{sample}.finished_all", sample=datasets, output_dir=output_dirs)
        expand(output_prefix+"{tool}/opal/{sample}.opal_report", sample=datasets, tool=tools)

rule copy_reads:
    params:
        in1=original_reads_dir + "/{sample}.1.fq.gz",
        in2=original_reads_dir + "/{sample}.2.fq.gz"
    output:
        r1=fastq_dir + "/{sample}.1.fq.gz",
        r2=fastq_dir + "/{sample}.2.fq.gz",
    shell:
        "pwd && mkdir -pv {fastq_dir} && cp -vL {params.in1} {params.in2} {fastq_dir}/"

def get_condensed_to_biobox_extra_args(tool):
    if tool == 'kracken':
        return ' --no-fill'
    else:
        return ''

rule condensed_to_biobox:
    input:
        profile = output_prefix + "{tool}/{tool}/{sample}.profile",
    params:
        truth = truth_dir + "/{sample}.condensed.biobox",
        extra_args = lambda wildcards: get_condensed_to_biobox_extra_args(wildcards.tool)
    output:
        biobox = output_prefix + "{tool}/biobox/{sample}.biobox",
    conda:
        "singlem-dev"
    shell:
        # Convert reports to singlem condense format
        # run opam against the truth
        "{singlem_git_base_directory}/extras/condensed_profile_to_biobox.py {params.extra_args} --input-condensed-table {input.profile} " \
        "--output-biobox {output.biobox} --template-biobox {params.truth} " \
        " > {output.biobox}"

rule opal:
    input:
        biobox = output_prefix+"{tool}/biobox/{sample}.biobox",
    params:
        truth = truth_dir + "/{sample}.condensed.biobox",
        output_dir = output_prefix+"{tool}",
        output_opal_dir = output_prefix+"{tool}/opal/{sample}.opal_output_directory",
    output:
        report=output_prefix+"{tool}/opal/{sample}.opal_report",
        done=output_prefix+"{tool}/opal/{sample}.opal_report.done",
    conda:
        'envs/opal.yml'
    shell:
        "opal.py -g {params.truth} -o {params.output_opal_dir} {input.biobox} || echo 'expected opal non-zero existatus'; mv {params.output_opal_dir}/results.tsv {output.report} && rm -rf {params.output_opal_dir} && touch {output.done}"


###############################################################################################
###############################################################################################
###############################################################################################
#########
######### tool-specific rules - singlem first

rule singlem_copy_metapackage:
    input:
        metapackage
    output:
        db=directory(singlem_metapackage),
        done=output_dirs_dict['singlem'] + "/singlem/data/done",
    shell:
        "cp -rL {input} {output.db} && touch {output.done}"

rule singlem_run_to_profile:
    input:
        r1=fastq_dir + "/{sample}.1.fq.gz",
        r2=fastq_dir + "/{sample}.2.fq.gz",
        db=singlem_metapackage,
        data_done=output_dirs_dict['singlem'] + "/singlem/data/done"
    benchmark:
        benchmark_dir + "/singlem/{sample}-"+str(num_threads)+"threads.benchmark"
    output:
        report=output_dirs_dict['singlem'] + "/singlem/{sample}.profile",
        done=output_dirs_dict['singlem'] + "/singlem/{sample}.profile.done"
    conda:
        "singlem-dev"
    threads:
        num_threads
    shell:
        "{singlem_git_base_directory}/bin/singlem pipe --threads {threads} -1 {input.r1} -2 {input.r2} -p {output.report} --metapackage {input.db} && touch {output.done}"

# rule singlem_run_to_archive:
#     input:
#         r1=fastq_dir + "/{sample}.1.fq.gz",
#         r2=fastq_dir + "/{sample}.2.fq.gz",
#         db=singlem_metapackage,
#         data_done=output_dirs_dict['singlem'] + "/singlem/data/done"
#     output:
#         report=output_dirs_dict['singlem'] + "/singlem/{sample}.json",
#         done=output_dirs_dict['singlem'] + "/singlem/{sample}.json.done"
#     conda:
#         "singlem-dev"
#     threads:
#         num_threads
#     shell:
#         "~/git/singlem/bin/singlem pipe --threads {threads} -1 {input.r1} -2 {input.r2} --archive-otu-table {output.report} --metapackage {input.db} && touch {output.done}"

# rule singlem_condense:
#     input:
#         archive=output_dirs_dict['singlem'] + "/singlem/{sample}.json",
#         db=singlem_metapackage,
#         data_done=output_dirs_dict['singlem'] + "/singlem/data/done"
#     output:
#         report=output_dirs_dict['singlem'] + "/singlem/{sample}.profile",
#         done=output_dirs_dict['singlem'] + "/singlem/{sample}.profile.done"
#     conda:
#         "singlem-dev"
#     shell:
#         "~/git/singlem/bin/singlem condense --input-archive-otu-table {input.archive} -p {output.report} --metapackage {input.db} && touch {output.done}"


###############################################################################################
###############################################################################################
###############################################################################################
#########
######### metaphlan


rule metaphlan_copy_db:
    input:
        # Cannot use the directory as input/output because humann complains when
        # there's a snakemake hidden file in the dir

        # db1=directory(metaphlan_db_original1),
        # db2=directory(metaphlan_db_original2),
    output:
        # db1=directory(metaphlan_db_local1),
        # db2=directory(metaphlan_db_local2),
        done=output_dirs_dict['metaphlan'] + "/metaphlan/data/done"
    shell:
        "cp -rvL {metaphlan_db_original1} {metaphlan_db_local1} && touch {output.done}"

rule metaphlan_profile:
    input:
        r1=fastq_dir + "/{sample}.1.fq.gz",
        r2=fastq_dir + "/{sample}.2.fq.gz",
        done=output_dirs_dict['metaphlan'] + "/metaphlan/data/done"
    benchmark:
        benchmark_dir + "/metaphlan/{sample}-"+str(num_threads)+"threads.benchmark"
    output:
        sgb_report=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.sgb_report",
        done=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.profile.done"
    conda:
        "envs/metaphlan.yml"
    threads: num_threads
    params:
        cat_reads = output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.cat.fq.gz",
    shell:
        # Concatenate input files because metaphlan can't handle multiple input files
        "rm -f {output.sgb_report} {params.cat_reads}.bowtie2out.txt; cat {input.r1} {input.r2} > {params.cat_reads} && metaphlan {params.cat_reads} --nproc {threads} --input_type fastq --bowtie2db {metaphlan_db_local1} -o {output.sgb_report} && touch {output.done}"

rule metaphlan_convert_profile_to_GTDB:
    input:
        report=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.sgb_report"
    output:
        gtdb_report=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.gtdb_profile",
        done=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.gtdb_report.done"
    conda:
        "envs/metaphlan.yml"
    shell:
        "sgb_to_gtdb_profile.py -i {input.report} -o {output.gtdb_report} -d {metaphlan_db_local1}/mpa_vOct22_CHOCOPhlAnSGB_202212.pkl && touch {output.done}"

rule metaphlan_profile_to_condensed:
    input:
        report=output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.gtdb_profile"
    output:
        profile = output_dirs_dict['metaphlan'] + "/metaphlan/{sample}.profile",
    conda:
        "singlem-dev"
    shell:
        "~/m/msingle/mess/105_novelty_testing/metaphlan_to_condensed.py --metaphlan {input} --sample {wildcards.sample} > {output.profile} "

###############################################################################################
###############################################################################################
###############################################################################################
#########
######### motus

rule motus_copy_db:
    input:
        db=motus_db_path_original,
    output:
        db=directory(motus_db_path_local),
        done=output_dirs_dict['motus'] + "/motus/data/done"
    shell:
        "mkdir -p {output.db} && rmdir {output.db} && cp -rvL {input.db} {output.db} && touch {output.done}"

rule motus_run:
    input:
        r1=fastq_dir + "/{sample}.1.fq.gz",
        r2=fastq_dir + "/{sample}.2.fq.gz",
        done=output_dirs_dict['motus'] + "/motus/data/done"
    benchmark:
        benchmark_dir + "/motus/{sample}-"+str(num_threads)+"threads.benchmark"
    output:
        report=output_dirs_dict['motus'] + "/motus/{sample}.motus",
        done=output_dirs_dict['motus'] + "/motus/{sample}.profile.done"
    threads: num_threads
    conda:
        "envs/motus.yml"
    shell:
        "motus profile -t {threads} -db {motus_db_path_local} -f {input.r1} -r {input.r2} -o {output.report} && touch {output.done}"

rule motus_profile_to_condensed:
    input:
        report=output_dirs_dict['motus'] + "/motus/{sample}.motus"
    output:
        profile = output_dirs_dict['motus'] + "/motus/{sample}.profile",
    conda:
        "singlem-dev"
    shell:
        "~/m/msingle/mess/105_novelty_testing/motus_to_condensed.py --motus {input.report} " \
        "--gtdb {motus_gtdb_tsv} " \
        " > {output.profile} "


###############################################################################################
###############################################################################################
###############################################################################################
######### bracken


rule braken_copy_data:
    output:
        db=directory(kraken_db_local),
        done=output_dirs_dict['kracken'] + "/kraken/data/done"
    shell:
        "cp -r {kracken_db} {output.db}/ && touch {output.done}"

rule kraken_run:
    input:
        reads_copied1 = fastq_dir + "/{sample}.1.fq.gz",
        reads_copied2 = fastq_dir + "/{sample}.2.fq.gz",
        db=kraken_db_local,
        copy_braken_data_done=output_dirs_dict['kracken'] + "/kraken/data/done"
    benchmark:
        benchmark_dir + "/kraken/{sample}-"+str(num_threads)+"threads.benchmark"
    threads: num_threads
    output:
        report=output_dirs_dict['kracken'] + "/kraken/{sample}.kraken",
        done=output_dirs_dict['kracken'] + "/kraken/{sample}.kraken.done"
    shell:
        "export PATH={kracken2_install}:$PATH && " \
        "kraken2 --db {input.db} --threads {threads} --output /dev/null --report {output.report} --paired {input.reads_copied1} {input.reads_copied2} && touch {output.done}"

rule braken_run:
    input:
        db=kraken_db_local,
        kraken_report=output_dirs_dict['kracken'] + "/kraken/{sample}.kraken",
        kraken_done=output_dirs_dict['kracken'] + "/kraken/{sample}.kraken.done"
    output:
        s=output_dirs_dict['kracken'] + "/braken/{sample}.report.S",
        g=output_dirs_dict['kracken'] + "/braken/{sample}.report.G",
        f=output_dirs_dict['kracken'] + "/braken/{sample}.report.F",
        o=output_dirs_dict['kracken'] + "/braken/{sample}.report.O",
        c=output_dirs_dict['kracken'] + "/braken/{sample}.report.C",
        p=output_dirs_dict['kracken'] + "/braken/{sample}.report.P",
        d=output_dirs_dict['kracken'] + "/braken/{sample}.report.D",
        done=output_dirs_dict['kracken'] + "/braken/{sample}.done"
    shell:
        "export PATH={bracken_install}:$PATH && " \
        "bracken -d {input.db} -r 150 -l S -t 10 -o {output.s} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l G -t 10 -o {output.g} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l F -t 10 -o {output.f} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l O -t 10 -o {output.o} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l C -t 10 -o {output.c} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l P -t 10 -o {output.p} -i {input.kraken_report} && " \
        "bracken -d {input.db} -r 150 -l D -t 10 -o {output.d} -i {input.kraken_report} && " \
        "touch {output.done}"


rule bracken_to_profile:
    input:
        output_dirs_dict['kracken'] + "/braken/{sample}.report.S",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.G",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.F",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.O",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.C",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.P",
        output_dirs_dict['kracken'] + "/braken/{sample}.report.D",
        output_dirs_dict['kracken'] + "/braken/{sample}.done"
    params:
        report_prefix = output_dirs_dict['kracken']+"/braken/{sample}.report",
        biobox_dir = output_dirs_dict['kracken']+'/biobox',
        truth = truth_dir + "/{sample}.condensed.biobox",
    output:
        profile = output_dirs_dict['kracken'] + "/kracken/{sample}.profile",
    conda:
        "singlem-dev"
    shell:
        # Convert reports to singlem condense format
        "mkdir -p {params.biobox_dir} && " \
        "~/m/msingle/mess/105_novelty_testing/kraken_to_biobox.py --report-prefix {params.report_prefix} " \
        "--bacterial-taxonomy ~/m/db/gtdb/gtdb_release207/bac120_taxonomy_r207.tsv " \
        "--archaeal-taxonomy ~/m/db/gtdb/gtdb_release207/ar53_taxonomy_r207.tsv > {output.profile}"

###############################################################################################
###############################################################################################
###############################################################################################
######### sourmash

rule copy_db:
    input:
        db1 = sourmash_db1_original,
        db2 = sourmash_db2_original,
    output:
        db1=sourmash_db1,
        db2=sourmash_db2,
        done=output_dirs_dict['sourmash'] + "/sourmash/data/done"
    params:
        output_dir = output_dirs_dict['sourmash'],
    shell:
        "mkdir -p {params.output_dir}/sourmash/data && cp -rvL {input.db1} {output.db1} && cp -rvL {input.db2} {output.db2} && touch {output.done}"

rule sourmash_run:
    input:
        r1=fastq_dir + "/{sample}.1.fq.gz",
        r2=fastq_dir + "/{sample}.2.fq.gz",
        db1=sourmash_db1,
        db2=sourmash_db2,
        done=output_dirs_dict['sourmash'] + "/sourmash/data/done"
    benchmark:
        benchmark_dir + "/sourmash/{sample}-"+str(num_threads)+"threads.benchmark"
    threads: num_threads
    output:
        report=output_dirs_dict['sourmash'] + "/sourmash/{sample}.gather_gtdbrs207_reps.with-lineages.csv",
        done=output_dirs_dict['sourmash'] + "/sourmash/{sample}.profile.done"
    conda:
        "envs/sourmash.yml"
    params:
        output_dir = output_dirs_dict['sourmash'],
        sourmash_prefix = lambda wildcards: output_dirs_dict['sourmash'] + "/sourmash/"+wildcards.sample
    shell:
        # Sourmash does not seem to have a --threads option
        # sourmash tax annotate creates a file with-lineages in the CWD, so we need to cd into the output dir before running it
        "sourmash sketch dna -p k=21,k=31,k=51,scaled=1000,abund --merge {params.sourmash_prefix} -o {params.sourmash_prefix}.sig {input.r1} {input.r2} && echo \"running gather..\" && sourmash gather {params.sourmash_prefix}.sig {input.db2} -o {params.sourmash_prefix}.gather_gtdbrs207_reps.csv && echo \"running tax ..\" && cd {params.output_dir}/sourmash && sourmash tax annotate -g {wildcards.sample}.gather_gtdbrs207_reps.csv -t ../../{input.db1} && cd - && touch {output.done}"

rule sourmash_to_condensed:
    input:
        output_dirs_dict['sourmash'] + "/sourmash/{sample}.gather_gtdbrs207_reps.with-lineages.csv",
    output:
        profile = output_dirs_dict['sourmash'] + "/sourmash/{sample}.profile",
    shell:
        "~/m/msingle/mess/105_novelty_testing/sourmash_to_condensed.py --with-lineages {input} " \
        "--sample {wildcards.sample} " \
        " > {output} "
