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
              sh '''cd std-build
                    chmod +x ./image-builder-7.sh
                    ./image-builder-7.sh -b aws-marketplace-upload-centos -k disk-images -R us-east-2'''  
            }
        }
        stage('Deploy Image Builder 8') {
            steps {
                sh 'chmod +x ./image-builder-8.sh -b aws-marketplace-upload-centos -k disk-images'
                sh './image-builder-8.sh'            
            }
        }
    }
}
