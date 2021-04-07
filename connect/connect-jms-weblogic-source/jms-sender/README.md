
STEPS			

1.install jdk to the test environment				
	
2.install weblogic to the test environment							

3.compile this project on your local machine or in the test environment (this's optional if you already have a compiled toolkit.zip)		
	
	install maven
	mvn clean package
	
4.deploy project to the test environment
	
	copy toolkit.zip to the test environment (if you just compiled peoject by maven, find it from target folder)		
	unzip toolkit.zip
	cd toolkit
	update config/config.properties	
	chmod +x bin/*.sh

5.update wlfullclient.jar if necessary (this's optional if your weblogic is 12.2.1.1.0)				
	
	./bin/updateWlfullclient.sh

6.prepare test domain					
	
	./bin/prepareDomain.sh		

7.start weblogic

8.start consumers

9.start producers

10.check result


	

