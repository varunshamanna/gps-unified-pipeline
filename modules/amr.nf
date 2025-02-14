// Run PBP AMR predictor to assign pbp genes and estimate samples' MIC (minimum inhibitory concentration) for 6 Beta-lactam antibiotics
process PBP_RESISTANCE {
    input:
    tuple val(sample_id), path(assembly)

    output:
    tuple val(sample_id), path("result.json"), emit: json

    shell:
    '''
    spn_pbp_amr !{assembly} > result.json
    '''
}

// Extract the results from the result.json file of the PBP AMR predictor
// 
// "=" character in MICs are replaced by "eq_sign" string to avoid issue when Nextflow attempt to capture string variables with "=" character 
// Reported to Nextflow team via issue nextflow-io/nextflow#3553, and a fix will be released with version 23.04.0 in 2023 April (ETA) 
process GET_PBP_RESISTANCE {
    input:
    tuple val(sample_id), path(json)

    output:
    tuple val(sample_id), env(pbp1a), env(pbp2b), env(pbp2x), env(AMX_MIC), env(AMX), env(CRO_MIC), env(CRO_NONMENINGITIS), env(CRO_MENINGITIS), env(CTX_MIC), env(CTX_NONMENINGITIS), env(CTX_MENINGITIS), env(CXM_MIC), env(CXM), env(MEM_MIC), env(MEM), env(PEN_MIC), env(PEN_NONMENINGITIS), env(PEN_MENINGITIS), emit: result

    shell:
    '''
    pbp1a=$(< !{json} jq -r .pbp1a)
    pbp2b=$(< !{json} jq -r .pbp2b)
    pbp2x=$(< !{json} jq -r .pbp2x)
    AMX_MIC=$(< !{json} jq -r .amxMic | sed -e 's/=/eq_sign/g')
    AMX=$(< !{json} jq -r .amx)
    CRO_MIC=$(< !{json} jq -r .croMic | sed -e 's/=/eq_sign/g')
    CRO_NONMENINGITIS=$(< !{json} jq -r .croNonMeningitis)
    CRO_MENINGITIS=$(< !{json} jq -r .croMeningitis)
    CTX_MIC=$(< !{json} jq -r .ctxMic | sed -e 's/=/eq_sign/g')
    CTX_NONMENINGITIS=$(< !{json} jq -r .ctxNonMeningitis)
    CTX_MENINGITIS=$(< !{json} jq -r .ctxMeningitis)
    CXM_MIC=$(< !{json} jq -r .cxmMic | sed -e 's/=/eq_sign/g')
    CXM=$(< !{json} jq -r .cxm)
    MEM_MIC=$(< !{json} jq -r .memMic | sed -e 's/=/eq_sign/g')
    MEM=$(< !{json} jq -r .mem)
    PEN_MIC=$(< !{json} jq -r .penMic | sed -e 's/=/eq_sign/g')
    PEN_NONMENINGITIS=$(< !{json} jq -r .penNonMeningitis)
    PEN_MENINGITIS=$(< !{json} jq -r .penMeningitis)
    '''
}