pipeline { 
    agent any 
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Cloning Git') {
            steps {
                git 'https://github.com/Internethamster/centos-2-awsmp.git'
            }
        } 
        stage('Clean Workspace and Checkout Source') {
            steps {
                deleteDir()
                checkout([$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [], submoduleCfg: [], userRemoteConfigs: [[credentialsId: 'davdunc-previous', url: 'git@github.com:Internethamster/centos-2-awsmp.git']]])
                notifyStash()
            }
        }
        stage('Initiate Pipeline') { 
            steps { 
                echo "Welcome from DevOps World" 
            }
        }
        stage('Deploy Image Builder 6') {
            steps {
                sh 'chmod +x image-builder-6.sh'
                sh './image-builder-6.sh'            
            }
        }
        stage('Deploy Image Builder 7') {
            steps {
                sh 'chmod +x image-builder-7.sh'
                sh './image-builder-7.sh'
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
