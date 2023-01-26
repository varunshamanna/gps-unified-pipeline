def version_message(String version) {
    println(
        """
        ==============================================
              GPS-unified-pipeline version ${version}
        ==============================================
        """.stripIndent()
    )
}

def help_message() {
    println(
        """
        Usage:
        The typical command for running the pipeline is as follows:
        nextflow run main.nf --reads /path/to/raw-reads-directory
        Mandatory arguments:
        --input_dir      Path to input directory containing the fastq files to be assembled
        --assembler      Assembler to use: shovill/unicycler'
        --output         Path to output directory
        """.stripIndent()
    )
}

def pipeline_start_message(String version, Map params){
    log.info "======================================================================"
    log.info "                  GPS-unified-pipeline"
    log.info "======================================================================"
    log.info "Running version   : ${version}"
    log.info "Fastq inputs      : ${params.reads}"
    log.info "Assembler         : ${params.assembler}"
    log.info ""
    log.info "-------------------------- Other parameters --------------------------"
    params.sort{ it.key }.each{ k, v ->
        if (v){
            log.info "${k}: ${v}"
        }
    }
    log.info "======================================================================"
    log.info "Outputs written to path '${params.output}'"
    log.info "======================================================================"
    
    log.info ""
}
def complete_message(Map params, nextflow.script.WorkflowMetadata workflow, String version){
    // Display complete message
    log.info ""
    log.info "Ran the workflow: ${workflow.scriptName} ${version}"
    log.info "Command line    : ${workflow.commandLine}"
    log.info "Completed at    : ${workflow.complete}"
    log.info "Duration        : ${workflow.duration}"
    log.info "Success         : ${workflow.success}"
    log.info "Work directory  : ${workflow.workDir}"
    log.info "Exit status     : ${workflow.exitStatus}"
    log.info ""
}

def error_message(nextflow.script.WorkflowMetadata workflow){
    // Display error message
    log.info ""
    log.info "Workflow execution stopped with the following message:"
    log.info "  " + workflow.errorMessage
}
