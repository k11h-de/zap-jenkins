// please adjust the next variables to your needs

def targets   = ['juice-shop.herokuapp.com', 'www.hackthissite.org', 'tryhackme.com']
def gitUrl    = "git@git.company.com:group/zap-jenkins.git"
def gitBranch = "origin/main"
def gitCredId = <jenkins-cred-id>

// no changes below here
// ------------------------------------------------------------

pipeline {
    agent { node { label 'docker' } }
    options {
		timestamps()
		buildDiscarder(logRotator(numToKeepStr: '100'))
		ansiColor('xterm')
	}
	parameters {
		choice(name: 'ZAP_TARGET', choices: targets, description:'Website to Scan')
		choice(name: 'ZAP_ALERT_LVL', choices: ['High', 'Medium', 'Low', 'Informational'], description: 'Level, when to alert, see Zap documentation, default High')
        booleanParam(name: 'ZAP_USE_CONTEXT_FILE', defaultValue: true, description: '')
        string(name: 'DELAY_IN_MS', defaultValue: '0', description: 'The delay in milliseconds between each request while scanning. Setting this to a non zero value will increase the time an active scan takes, but will put less of a strain on the target host.')
        string(name: 'MAX_SCAN_DURATION_IN_MINS', defaultValue: '300', description: 'The maximum time that the whole scan can run for in minutes. Zero means no limit. This can be used to ensure that a scan is completed around a set time.' )
	}
    triggers {
        parameterizedCron('''H 23 * * 2,4,6 %ZAP_TARGET=juice-shop.herokuapp.com
H 23 * * 1,3,5 %ZAP_TARGET=www.hackthissite.org;ZAP_USE_CONTEXT_FILE=false;DELAY_IN_MS=50
H 21 * * 1,3,5 %ZAP_TARGET=tryhackme.com;ZAP_ALERT_LVL=Medium;MAX_SCAN_DURATION_IN_MINS=60
''')
    }
	stages {
		stage('checkout'){
			steps{
				script {
                    currentBuild.displayName = env.BUILD_NUMBER + "_" + params.ZAP_TARGET + "--" + params.ZAP_ALERT_LVL
					cleanWs()     
				}
                // checkout
                checkout([
                    $class: 'GitSCM',
                    branches: [[
                        name: gitBranch
                    ]],
                    userRemoteConfigs: [[
                        credentialsId: gitCredId ,
                        url: gitUrl
                    ]]
                ])
			}
		}
		stage('scanning'){
			steps{
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    sh("""
                        #!/bin/bash -eux
                        ZAP_TARGET=${params.ZAP_TARGET}                        
                        ZAP_ALERT_LVL=${params.ZAP_ALERT_LVL}
                        ZAP_USE_CONTEXT_FILE=${params.ZAP_USE_CONTEXT_FILE}
                        
                        # ensure report folder
                        mkdir -p results/

                        # starting container
                        docker run --name zap_${env.BUILD_NUMBER} -d owasp/zap2docker-stable zap.sh -daemon \
                        -port 2375 \
                        -host 127.0.0.1 \
                        -config api.disablekey=true \
                        -config scanner.attackOnStart=true \
                        -config scanner.delayInMs=${params.DELAY_IN_MS} \
                        -config scanner.maxScanDurationInMins=${params.MAX_SCAN_DURATION_IN_MINS} \
                        -config scanner.threadPerHost=2 \
                        -config view.mode=attack \
                        -config connection.dnsTtlSuccessfulQueries=-1 \
                        -config api.addrs.addr.name=.* \
                        -config api.addrs.addr.regex=true \
                        -addoninstall ascanrulesBeta \
                        -addoninstall pscanrulesBeta \
                        -addoninstall alertReport

                        # copy context file into container if exists
                        if [[ -f "./contexts/\${ZAP_TARGET}.context" ]]; then
                            echo "context file found in contexts/\${ZAP_TARGET}.context - Copying into container"
                            docker cp ./contexts/\${ZAP_TARGET}.context zap_${env.BUILD_NUMBER}:/home/zap/$ZAP_TARGET
                            docker cp ./contexts/default.context zap_${env.BUILD_NUMBER}:/home/zap/default
                        else
                            echo "context file not found in contexts/\${ZAP_TARGET}.context - Running scan with default context."
                            ZAP_USE_CONTEXT_FILE="false"
                            docker cp ./contexts/default.context zap_${env.BUILD_NUMBER}:/home/zap/default
                        fi

                        # wait for zap to be ready
                        docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 status -t 120

                        # start the actual scan, with or without context file
                        if [[ "\${ZAP_USE_CONTEXT_FILE}" == "true" ]]; then
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 context import /home/zap/$ZAP_TARGET
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 context info $ZAP_TARGET
                            # required to work aroung bug https://github.com/Grunny/zap-cli/issues/79 
                            if [[ -f "./contexts/\${ZAP_TARGET}.context.exclude" ]]; then
                                echo "context exclude file found in contexts/\${ZAP_TARGET}.context.exclude - applying."
                                cat ./contexts/\${ZAP_TARGET}.context.exclude | while read line || [[ -n $line ]];
                                do
                                    docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 exclude "\$line"
                                done
                            fi
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 open-url https://$ZAP_TARGET
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 spider -c $ZAP_TARGET https://$ZAP_TARGET
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 active-scan -c $ZAP_TARGET --recursive https://$ZAP_TARGET
                        else
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 context import /home/zap/default
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 context info default
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 open-url https://$ZAP_TARGET
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 spider -c default https://$ZAP_TARGET
                            docker exec zap_${env.BUILD_NUMBER} zap-cli -v -p 2375 active-scan -c default --recursive https://$ZAP_TARGET
                        fi

                        # generate report inside container
                        docker exec zap_${env.BUILD_NUMBER} zap-cli -p 2375 report -o /home/zap/report.html -f html
                        docker cp zap_${env.BUILD_NUMBER}:/home/zap/report.html ./results/
                        docker exec zap_${env.BUILD_NUMBER} zap-cli -p 2375 report -o /home/zap/report.xml -f xml
                        docker cp zap_${env.BUILD_NUMBER}:/home/zap/report.xml ./results/
                        # fetch alerts json
                        docker exec zap_${env.BUILD_NUMBER} zap-cli -p 2375 alerts --alert-level "Informational" -f json > ./results/report.json || true

                        # Check for alerts
                        ALERT_CNT=\$(docker exec zap_${env.BUILD_NUMBER} zap-cli -p 2375 alerts --alert-level $ZAP_ALERT_LVL -f json | jq length)

                        # mark jenkins job yellow in case alerts were detected
                        if [[ "\${ALERT_CNT}" -gt 0 ]]; then
                            echo "Vulnerabilities dectected, Lvl=$ZAP_ALERT_LVL Alert count=\${ALERT_CNT}"
                            echo "Job is unstable..."
                            exit 1
                        fi
                    """)
                }
			}
		}
        stage('publish'){
            steps {
				publishHTML([
                    allowMissing: true,
				    alwaysLinkToLastBuild: true,
				    keepAll: true,
                    reportDir: './results',
                    reportFiles: 'report.html,report.xml,report.json',
                    reportName: 'Scan-Report',
                    reportTitles: 'HTML, XML, JSON'
                ])
			}
		}
	}
	post {
        always {
            sh("""
                #!/bin/bash -eux
                docker container rm -f zap_${env.BUILD_NUMBER} || true
            """)
        }	
	}
}
