component extends="wirebox.system.ioc.config.Binder"{
	
	function configure(){
		
		map("mongoFactory")
			.to("cfmongodb.core.JavaloaderFactory");
			//use cfmongodb.core.DefaultFactory to load mongodb jars in your CF classpath
		
		map("mongoConfig")
			.to("cfmongodb.core.MongoConfig")
			.initArg(name="dbName",value="mongorocks")
			.initArg(name="mongoFactory", ref="mongoFactory");
			
		map("mongo")
			.to("cfmongodb.core.Mongo")
			.initArg(name="mongoConfig", ref='mongoConfig');
	}
	
}