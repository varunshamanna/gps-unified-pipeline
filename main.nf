#!/usr/bin/env nextflow
nextflow.enable.dsl=2
//Import non-process modules
include {help_message; version_message; complete_message; error_message; pipeline_start_message} from './modules/messages'
include {help_or_version} from './modules/params_utilities'

version = '1.0'

// Import modules
include { PREPROCESS; GET_BASES } from "$projectDir/modules/preprocess"
include { ASSEMBLY_UNICYCLER; ASSEMBLY_SHOVILL; ASSEMBLY_ASSESS; ASSEMBLY_QC } from "$projectDir/modules/assembly"
include { GET_REF_GENOME_BWA_DB_PREFIX; MAPPING; SAM_TO_SORTED_BAM; REF_COVERAGE; SNP_CALL; HET_SNP_COUNT; MAPPING_QC } from "$projectDir/modules/mapping"
include { GET_KRAKEN_DB; TAXONOMY; TAXONOMY_QC } from "$projectDir/modules/taxonomy"
include { OVERALL_QC } from "$projectDir/modules/overall_qc"
include { GET_POPPUNK_DB; GET_POPPUNK_EXT_CLUSTERS; LINEAGE } from "$projectDir/modules/lineage"
include { GET_SEROBA_DB; CREATE_SEROBA_DB; SEROTYPE } from "$projectDir/modules/serotype"
include { MLST } from "$projectDir/modules/mlst"
include { PBP_RESISTANCE; GET_PBP_RESISTANCE } from "$projectDir/modules/amr"

// help and version messages
help_or_version(params, version)
//final_params = check_params(merged_params)
// starting pipeline
pipeline_start_message(version, final_params)



// Main workflow
workflow {
    // Get path to prefix of Reference Genome BWA Database, generate from assembly if necessary
    ref_genome_bwa_db_prefix = GET_REF_GENOME_BWA_DB_PREFIX(params.ref_genome, params.ref_genome_bwa_db_local)

    // Get path to Kraken2 Database, download if necessary
    kraken2_db = GET_KRAKEN_DB(params.kraken2_db_remote, params.kraken2_db_local)

    // Get path to SeroBA Databases, clone and rebuild if necessary
    GET_SEROBA_DB(params.seroba_remote, params.seroba_local)
    seroba_db = CREATE_SEROBA_DB(params.seroba_local, GET_SEROBA_DB.out.create_db)

    // Get paths to PopPUNK Database and External Clusters, download if necessary
    poppunk_db = GET_POPPUNK_DB(params.poppunk_db_remote, params.poppunk_db_local)
    poppunk_ext_clusters = GET_POPPUNK_EXT_CLUSTERS(params.poppunk_ext_clusters_remote, params.poppunk_db_local)

    // Get read pairs into Channel raw_read_pairs_ch
    raw_read_pairs_ch = Channel.fromFilePairs( "$params.reads/*_{,R}{1,2}{,_001}.{fq,fastq}{,.gz}", checkIfExists: true )

    // Preprocess read pairs
    // Output into Channels PREPROCESS.out.processed_reads & PREPROCESS.out.json
    PREPROCESS(raw_read_pairs_ch)

    // From Channel PREPROCESS.out.processed_reads, assemble the preprocess read pairs
    // Output into Channel ASSEMBLY_ch, and hardlink the assemblies to $params.output directory
    if ( params.assembler == "shovill" ) {
        ASSEMBLY_ch = ASSEMBLY_SHOVILL(PREPROCESS.out.processed_reads)
    } else if ( params.assembler == "unicycler" ) {
        ASSEMBLY_ch = ASSEMBLY_UNICYCLER(PREPROCESS.out.processed_reads)
    } else {
        println "Provided assembler option is not valid. Supported value: shovill, unicycler"
        System.exit(0)
    }

    // From Channel ASSEMBLY_ch, assess assembly quality
    ASSEMBLY_ASSESS(ASSEMBLY_ch)

    // From Channel ASSEMBLY_ASSESS.out.report and Channel GET_BASES(PREPROCESS.out.json), provide Assembly QC status
    // Output into Channels ASSEMBLY_QC.out.detailed_result & ASSEMBLY_QC.out.result
    ASSEMBLY_QC(
        ASSEMBLY_ASSESS.out.report
        .join(GET_BASES(PREPROCESS.out.json), failOnDuplicate: true, failOnMismatch: true)
    )
    
    // From Channel PREPROCESS.out.processed_reads map reads to reference
    // Output into Channel MAPPING.out.sam
    MAPPING(ref_genome_bwa_db_prefix, PREPROCESS.out.processed_reads)

    // From Channel MAPPING.out.sam, Convert SAM into sorted BAM
    // Output into Channel SAM_TO_SORTED_BAM.out.bam
    SAM_TO_SORTED_BAM(MAPPING.out.sam)

    // From Channel SAM_TO_SORTED_BAM.out.bam calculates reference coverage and non-cluster Het-SNP site count respecitvely
    // Output into Channels REF_COVERAGE.out.result & HET_SNP_COUNT.out.result respectively
    REF_COVERAGE(SAM_TO_SORTED_BAM.out.bam)
    SNP_CALL(params.ref_genome, SAM_TO_SORTED_BAM.out.bam) | HET_SNP_COUNT

    // Merge Channels REF_COVERAGE.out.result & HET_SNP_COUNT.out.result to provide Mapping QC Status
    // Output into Channels MAPPING_QC.out.detailed_result & MAPPING_QC.out.result
    MAPPING_QC(
        REF_COVERAGE.out.result
        .join(HET_SNP_COUNT.out.result, failOnDuplicate: true, failOnMismatch: true)
    )

    // From Channel PREPROCESS.out.processed_reads assess Streptococcus pneumoniae percentage in reads
    // Output into Channels TAXONOMY.out.detailed_result & TAXONOMY.out.result report
    TAXONOMY(kraken2_db, params.kraken2_memory_mapping, PREPROCESS.out.processed_reads)

    // From Channel TAXONOMY.out.report, provide taxonomy QC status
    // Output into Channels TAXONOMY_QC.out.detailed_result & TAXONOMY_QC.out.result report
    TAXONOMY_QC(TAXONOMY.out.report)

    // Merge Channels ASSEMBLY_QC.out.result & MAPPING_QC.out.result & TAXONOMY_QC.out.result to provide Overall QC Status
    // Output into Channel OVERALL_QC.out.result
    OVERALL_QC(
        ASSEMBLY_QC.out.result
        .join(MAPPING_QC.out.result, failOnDuplicate: true, failOnMismatch: true)
        .join(TAXONOMY_QC.out.result, failOnDuplicate: true, failOnMismatch: true)
    )

    // From Channel PREPROCESS.out.processed_reads, only output reads of samples passed overall QC based on Channel OVERALL_QC.out.result
    QC_PASSED_READS_ch = OVERALL_QC.out.result.join(PREPROCESS.out.processed_reads, failOnDuplicate: true, failOnMismatch: true)
                        .filter { it[1] == "PASS" }
                        .map { it -> it[0, 2..-1] }

    // From Channel ASSEMBLY_ch, only output assemblies of samples passed overall QC based on Channel OVERALL_QC.out.result
    QC_PASSED_ASSEMBLIES_ch = OVERALL_QC.out.result.join(ASSEMBLY_ch, failOnDuplicate: true, failOnMismatch: true)
                            .filter { it[1] == "PASS" }
                            .map { it -> it[0, 2..-1] }

    // From Channel QC_PASSED_ASSEMBLIES_ch, generate PopPUNK query file containing assemblies of samples passed overall QC 
    // Output into POPPUNK_QFILE
    POPPUNK_QFILE = QC_PASSED_ASSEMBLIES_ch
                    .map{ it.join'\t'}
                    .collectFile(name: "qfile.txt", newLine: true)

    // From generated POPPUNK_QFILE, assign GPSC to samples passed overall QC
    LINEAGE(poppunk_db, poppunk_ext_clusters, POPPUNK_QFILE)

    // From Channel QC_PASSED_READS_ch, serotype the preprocess reads of samples passed overall QC
    // Output into Channel SEROTYPE.out.result
    SEROTYPE(seroba_db, QC_PASSED_READS_ch)

    // From Channel QC_PASSED_ASSEMBLIES_ch, PubMLST typing the assemblies of samples passed overall QC
    // Output into Channel MLST.out.result
    MLST(QC_PASSED_ASSEMBLIES_ch)

    // From Channel QC_PASSED_ASSEMBLIES_ch, assign PBP genes and estimate MIC (minimum inhibitory concentration) for 6 Beta-lactam antibiotics
    // Output into Channel GET_PBP_RESISTANCE.out.result
    PBP_RESISTANCE(QC_PASSED_ASSEMBLIES_ch)
    GET_PBP_RESISTANCE(PBP_RESISTANCE.out.json)

    // Generate summary.csv by sorted sample_id based on merged Channels 
    // ASSEMBLY_QC.out.detailed_result,
    // MAPPING_QC.out.detailed_result,
    // TAXONOMY_QC.out.detailed_result,
    // OVERALL_QC.out.result,
    // LINEAGE.out.csv,
    // SEROTYPE.out.result,
    // MLST.out.result
    // GET_PBP_RESISTANCE.out.result
    // 
    // Replace null with approiate amount of "_" items when sample_id does not exist in that output (i.e. QC rejected)
    ASSEMBLY_QC.out.detailed_result
    .join(MAPPING_QC.out.detailed_result, failOnDuplicate: true, failOnMismatch: true)
    .join(TAXONOMY_QC.out.detailed_result, failOnDuplicate: true, failOnMismatch: true)
    .join(OVERALL_QC.out.result, failOnDuplicate: true, failOnMismatch: true)
    .join(LINEAGE.out.csv.splitCsv(skip: 1), failOnDuplicate: true, remainder: true)
        .map { it -> (it[-1] == null) ? it[0..-2] + ["_"]: it}
    .join(SEROTYPE.out.result, failOnDuplicate: true, remainder: true)
        .map { it -> (it[-1] == null) ? it[0..-2] + ["_"] * 2 : it}
    .join(MLST.out.result, failOnDuplicate: true, remainder: true)
        .map { it -> (it[-1] == null) ? it[0..-2] + ["_"] * 8: it}
    .join(GET_PBP_RESISTANCE.out.result.map { it -> it*.replaceAll("eq_sign", "=") }, failOnDuplicate: true, remainder: true) // Revert the equal sign workaround, refer to amr.nf for details
        .map { it -> (it[-1] == null) ? it[0..-2] + ["_"] * 18: it}
    .map { it.join',' }
    .collectFile(
        name: "summary.csv",
        storeDir: "$params.output",
        seed: [
                "Sample_ID",
                "Contigs#" , "Assembly_Length", "Seq_Depth", "Assembly_QC", 
                "Ref_Cov_%", "Het-SNP#" , "Mapping_QC",
                "S.Pneumo_%", "Taxonomy_QC",
                "Overall_QC",
                "GPSC",
                "Serotype", "SeroBA_Comment", 
                "ST", "aroE", "gdh", "gki", "recP", "spi", "xpt", "ddl",
                "pbp1a", "pbp2b", "pbp2x", "AMX_MIC", "AMX_Res", "CRO_MIC", "CRO_Res(Non-meningital)", "CRO_Res(Meningital)", "CTX_MIC", "CTX_Res(Non-meningital)", "CTX_Res(Meningital)", "CXM_MIC", "CXM_Res", "MEM_MIC", "MEM_Res", "PEN_MIC", "PEN_Res(Non-meningital)", "PEN_Res(Meningital)"
            ].join(","),
        sort: { it -> it.split(",")[0] },
        newLine: true
    )
}