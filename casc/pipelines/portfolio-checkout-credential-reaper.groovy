/* JENKINS_PORTFOLIO_CREDENTIAL_STORE_HELPERS */

pipeline {
    agent none

    options {
        timeout(time: 5, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    stages {
        stage('Remove expired temporary checkout credentials') {
            steps {
                script {
                    portfolioCleanupStaleCheckoutCredentials(currentBuild.rawBuild, 65 * 60 * 1000L)
                    echo 'Expired portfolio checkout credentials were checked in the dedicated folder store.'
                }
            }
        }
    }
}
