pipeline { 
    agent any 
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Clean Workspace and Checkout Source') {
            steps {
                deleteDir()
                checkout([$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [], submoduleCfg: [], userRemoteConfigs: [[credentialsId: 'davdunc-previous', url: 'git@github.com:Internethamster/centos-2-awsmp.git']]])
            }
        }
        stage('Deploy Image Builder 7') {
            steps {
                sh 'chmod +x ./std-build/image-builder-7.sh'
                sh './std-build/image-builder-7.sh -b aws-marketplace-upload-centos -k disk-images'
            }
        }
        stage('Deploy Image Builder 8') {
            steps {
                sh 'chmod +x ./image-builder-8.sh'
                sh './image-builder-8.sh'            
            }
        }
    }
}
