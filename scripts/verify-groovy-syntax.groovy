import groovy.json.JsonOutput
import org.codehaus.groovy.control.SourceUnit

def replacementsByFile = [
    'repository-pilot.groovy': [
        '/* JENKINS_PILOT_CANDIDATE_PATH_RULES */': ['web/', '.github/workflows/cloudflare-candidate.yml'],
        '/* JENKINS_PILOT_TRUSTED_PR_AUTHORS */': ['syntax-check-owner'],
        '/* JENKINS_PILOT_PRIMARY_CHECK_NAME */': 'jenkins-pr-gate',
        '/* JENKINS_PILOT_CANDIDATE_CHECK_NAME */': 'cloudflare-candidate',
        '/* JENKINS_PILOT_APP_DIRECTORY */': 'web',
        '/* JENKINS_PILOT_TUTOR_WEB_DIRECTORY */': 'tutor-web',
        '/* JENKINS_PILOT_SITE_URL */': 'https://example.invalid'
    ],
    'e2e.groovy': [
        '/* JENKINS_PILOT_E2E_REPOSITORY */': 'git@github.com:syntax-check-owner/syntax-check-repository.git',
        '/* JENKINS_PILOT_E2E_DETAILS_BASE */': 'https://github.com/syntax-check-owner/syntax-check-repository/commit/',
        '/* JENKINS_PILOT_E2E_CHECKOUT_CREDENTIAL_ID */': 'syntax-check-checkout',
        '/* JENKINS_PILOT_E2E_APP_CREDENTIAL_ID */': 'syntax-check-app',
        '/* JENKINS_PILOT_E2E_APP_ID */': '12345678',
        '/* JENKINS_PILOT_E2E_REPOSITORY_OWNER */': 'syntax-check-owner',
        '/* JENKINS_PILOT_E2E_REPOSITORY_NAME */': 'syntax-check-repository',
        '/* JENKINS_PILOT_E2E_APP_DIRECTORY */': 'web'
    ],
    'secondary-repository.groovy': [
        '/* JENKINS_SECONDARY_OWNER */': 'syntax-check-owner',
        '/* JENKINS_SECONDARY_REPOSITORY */': 'syntax-check-repository',
        '/* JENKINS_SECONDARY_TRUSTED_AUTHORS */': ['syntax-check-owner'],
        '/* JENKINS_SECONDARY_PRIMARY_CHECK_NAME */': 'jenkins-pr-gate',
        '/* JENKINS_SECONDARY_SMOKE_CHECK_NAME */': 'jenkins-production-smoke',
        '/* JENKINS_SECONDARY_SMOKE_URL */': ''
    ]
]

if (args.length == 0) {
    throw new IllegalArgumentException('Pass one or more trusted Jenkins Groovy source paths.')
}

args.each { sourcePath ->
    def sourceFile = new File(sourcePath)
    def source = sourceFile.getText('UTF-8')
    def replacements = replacementsByFile[sourceFile.name] ?: [:]

    replacements.each { marker, value ->
        if (source.count(marker) != 1) {
            throw new IllegalStateException("${sourceFile.name} must contain exactly one ${marker} template marker.")
        }
        source = source.replace(marker, JsonOutput.toJson(value))
    }

    SourceUnit.create(sourceFile.canonicalPath, source).parse()
    println "Groovy ${GroovySystem.version} syntax valid: ${sourceFile.name}"
}
