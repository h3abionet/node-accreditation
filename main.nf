#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/subdata
========================================================================================
 nf-core/subdata Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/subdata
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/subdata --csv '*_R{1,2}.fastq.gz' -profile uiuc_biocluster

    Mandatory arguments:
      -csv                          Path to CSV file to be subsampled
      -dir                          Location of FASTQ data; by default this is relative to the working directory path
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Optional arguments:
      -seed                         A random seed that fed to seqtk for subsamping.

    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}

// Check if genome exists in the config file
// if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
//     exit 1, "The provided genome '${params.genome}' is not available in the iGenomes file. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
// }

// TODO nf-core: Add any reference files that are needed
// Configurable reference genomes
// fasta = params.genome ? params.genomes[ params.genome ].fasta ?: false : false
// if ( params.fasta ){
//     fasta = file(params.fasta)
//     if( !fasta.exists() ) exit 1, "Fasta file not found: ${params.fasta}"
// }
//
// NOTE - THIS IS NOT USED IN THIS PIPELINE, EXAMPLE ONLY
// If you want to use the above in a process, define the following:
//   input:
//   file fasta from fasta
//


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}


if( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
// ch_multiqc_config = Channel.fromPath(params.multiqc_config)
// ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")

/*
 * Create a channel for input read files
 */

// if(params.readPaths){
//     if(params.singleEnd){
//         Channel
//             .from(params.readPaths)
//             .map { row -> [ row[0], [file(row[1][0])]] }
//             .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
//             .into { read_files_fastqc; read_files_trimming }
//     } else {
//         Channel
//             .from(params.readPaths)
//             .map { row -> [ row[0], [file(row[1][0]), file(row[1][1])]] }
//             .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
//             .into { read_files_fastqc; read_files_trimming }
//     }
// } else {
//     Channel
//         .fromFilePairs( params.reads, size: params.singleEnd ? 1 : 2 )
//         .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\nIf this is single-end data, please specify --singleEnd on the command line." }
//         .into { read_files_fastqc; read_files_trimming }
// }


// Header log info
log.info nfcoreHeader()
def summary = [:]
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['CSV']              = params.csv
summary['Dir']              = params.dir
// summary['Fasta Ref']        = params.fasta
// summary['Data Type']        = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if(workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if(workflow.profile == 'awsbatch'){
   summary['AWS Region']    = params.awsregion
   summary['AWS Queue']     = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if(params.config_profile_description) summary['Config Description'] = params.config_profile_description
if(params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if(params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if(params.email) {
  summary['E-mail Address']  = params.email
  summary['MultiQC maxsize'] = params.maxMultiqcEmailFileSize
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "\033[2m----------------------------------------------------\033[0m"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-subdata-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/subdata Workflow Summary'
    section_href: 'https://github.com/nf-core/subdata'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}

/*
 * Create channels for input fastq files
 */
// if (params.single_end) {
//     ch_design_reads_csv
//         .splitCsv(header:true, sep:',')
//         .map { row -> [ row.sample_id, [ file(row.fastq_1, checkIfExists: true) ] ] }
//         .into { ch_raw_reads_fastqc;
//                 ch_raw_reads_trimgalore }
// } else {

// At the moment we're only running with the already split files (which are also CSV)
// and which are all PE data; we can make this more flexible as needed
Channel.fromPath(params.csv)
    .splitCsv(header:true, sep:',')
    .map { row -> [ row.SampleName, [ file("${params.dir}/${row.R1}", checkIfExists: true), file("${params.dir}/${row.R2}", checkIfExists: true) ] ] }
    .into { ch_raw_reads_seqtk }

//             
// }


/*
 * Parse software version numbers
 */
// process get_software_versions {
//     publishDir "${params.outdir}/pipeline_info", mode: 'copy',
//     saveAs: {filename ->
//         if (filename.indexOf(".csv") > 0) filename
//         else null
//     }
// 
//     output:
//     file 'software_versions_mqc.yaml' into software_versions_yaml
//     file "software_versions.csv"
// 
//     script:
//     // TODO nf-core: Get all tools to print their version number here
//     """
//     echo $workflow.manifest.version > v_pipeline.txt
//     echo $workflow.nextflow.version > v_nextflow.txt
//     fastqc --version > v_fastqc.txt
//     multiqc --version > v_multiqc.txt
//     scrape_software_versions.py &> software_versions_mqc.yaml
//     """
// }


/* 
 * STEP 1: Split original CSV into subgroups
 */

// process splitCSV {
//     tag "$name"
//     publishDir "${params.outdir}/fastqc", mode: 'copy',
//         saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}
// 
//     input:
//     set val(name), file(reads) from read_files_fastqc
// 
//     output:
//     file "*_fastqc.{zip,html}" into fastqc_results
// 
//     script:
//     """
//     fastqc -q $reads
//     """
// }

/*
 * STEP 2 - Subsample the FASTQ files
 */

process sampleSeq {
    tag "Sample-${name}"
    publishDir "${params.outdir}/Subsample", mode: 'copy'
    
    input:
    set val(name), file(reads) from ch_raw_reads_seqtk

    output:
    set val(name), file("*.fastq.gz") into md5

    script:
    """
    seqtk sample -s ${params.setSeed} ${reads[0]} ${params.subsampleFrac} | pigz -p ${task.cpus} - > $name.${params.setSeed}.R1.fastq.gz
    seqtk sample -s ${params.setSeed} ${reads[1]} ${params.subsampleFrac} | pigz -p ${task.cpus} - > $name.${params.setSeed}.R2.fastq.gz
    
    """
}

process md5sum {
    tag "md5-${name}"
    
    input:
    set val(name), file(reads) from md5

    output:
    file "*.md5" into md5cat

    script:
    """
    md5sum $reads > ${name}.md5
    """
}

process md5sum_collect {
    tag "md5cat"
    publishDir "${params.outdir}/Subsample", mode: 'copy'
    
    input:
    file("*") from md5cat.collect()

    output:
    file "all.md5"

    script:
    """
    cat *.md5 >> all.md5
    """
}


/*
 * STEP 3 - Output Description HTML
 */
// process output_documentation {
//     publishDir "${params.outdir}/pipeline_info", mode: 'copy'
// 
//     input:
//     file output_docs from ch_output_docs
// 
//     output:
//     file "results_description.html"
// 
//     script:
//     """
//     markdown_to_html.r $output_docs results_description.html
//     """
// }


/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/subdata] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[nf-core/subdata] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if(workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // TODO nf-core: If not using MultiQC, strip out this code (including params.maxMultiqcEmailFileSize)
    // On success try attach the multiqc report
    def mqc_report = null
    try {
        if (workflow.success) {
            mqc_report = multiqc_report.getVal()
            if (mqc_report.getClass() == ArrayList){
                log.warn "[nf-core/subdata] Found multiple reports from process 'multiqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
    } catch (all) {
        log.warn "[nf-core/subdata] Could not attach MultiQC report to summary email"
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.maxMultiqcEmailFileSize.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/subdata] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[nf-core/subdata] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCountFmt > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCountFmt} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCountFmt} ${c_reset}"
    }

    if(workflow.success){
        log.info "${c_purple}[nf-core/subdata]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[nf-core/subdata]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader(){
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    ${c_dim}----------------------------------------------------${c_reset}
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/subdata v${workflow.manifest.version}${c_reset}
    ${c_dim}----------------------------------------------------${c_reset}
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if(params.hostnames){
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if(hostname.contains(hname) && !workflow.profile.contains(prof)){
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
