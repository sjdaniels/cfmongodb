<!---
NOTE: a number of these unit tests run ensureIndex(). This is because Marc likes to run mongo with --notablescan during development, and queries
against unindexed fields will fail, thus throwing off the tests.

You should absolutely NOT run an ensureIndex on your columns every time you run a query!

 --->
<cfcomponent output="false" extends="mxunit.framework.TestCase">
<cfscript>
import cfmongodb.core.*;


	javaloaderFactory = createObject('component','cfmongodb.core.JavaloaderFactory').init();
	mongoConfig = createObject('component','cfmongodb.core.MongoConfig').init(dbName="cfmongodb_tests", mongoFactory=javaloaderFactory);
	//mongoConfig = createObject('component','cfmongodb.core.MongoConfig').init(dbName="cfmongodb_tests");


	function setUp(){
		mongo = createObject('component','cfmongodb.core.Mongo').init(mongoConfig);
		col = 'people';
		dbCol = mongo.getDBCollection( col );
		atomicCol = 'atomictests';
		deleteCol = 'deletetests';

		commonSetUp();
	}

	function tearDown(){
		commonTearDown();
	}

	function testListCommandsViaMongoDriver(){
		var result = mongo.getMongoDB().command("listCommands");
		//debug(result);
		assertTrue( structKeyExists(result, "commands") );
		//NOTE: this is not a true CF struct, but a regular java hashmap; consequently, it is case sensitive!
		assertTrue( structCount(result["commands"]) GT 1);
	}

	function isAuthenticationRequired_should_return_true_if_index_queries_fail(){
		//guard
		var result = mongo.isAuthenticationRequired();
		assertFalse(result, "queries against an un-authed mongod should not cause errors");

		//now spoof the authentication failure
		injectMethod(mongo, this, "getIndexesFailOverride", "getIndexes");
		result = mongo.isAuthenticationRequired();
		assertTrue(result, "when a simple find query fails, we assume authentication is required");
	}

	private function getIndexesFailOverride(){
		throw("authentication failed");
	}


	/** test java getters */
	function testGetMongo(){
	  assertIsTypeOf( mongo, "cfmongodb.core.Mongo" );
	}

	function getMongo_should_return_underlying_java_Mongo(){
		var jMongo = mongo.getMongo();
		assertEquals("com.mongodb.Mongo",jMongo.getClass().getCanonicalName());
	}

	function getMongoDB_should_return_underlying_java_MongoDB(){

		var jMongoDB = mongo.getMongoDB(mongoConfig);
		assertEquals("com.mongodb.DBApiLayer",jMongoDB.getClass().getCanonicalName());
	}

	/** dumping grounnd for proof of concept tests */

	function poc_profiling(){
		var u = mongo.getMongoUtil();
		var command = u.toMongo({"profile"=2});
		var result = mongo.getMongoDB().command( command );
		//debug(result);

		var result = mongo.query("system.profile").find(limit=50,sort={"ts"=-1}).asArray();
		//debug(result);

		command = u.toMongo({"profile"=0});
		result = mongo.getMongoDB().command( command );
		//debug(result);
	}

	private function flush(){
		//forces mongo to flush
		mongo.getMongoDB().getLastError();
	}

	function newDBObject_should_be_acceptably_fast(){
		var i = 1;
		var count = 500;
		var u = mongo.getMongoUtil();
		var st = {string="string",number=1,float=1.5,date=now(),boolean=true};
		//get the first one out of its system
		var dbo = u.toMongo( st );
		var startTS = getTickCount();
		for(i=1; i LTE count; i++){
			dbo = u.toMongo( st );
		}
		var total = getTickCount() - startTS;
		assertTrue( total lt 200, "total should be acceptably fast but was #total#" );
	}

	function newDBObject_should_create_correct_datatypes(){
		var origNums = mongo.query( col ).$eq("number", types.number).count();
		var origNestedNums = mongo.query( col ).$eq("types.number", types.number).count();
		var origBool = mongo.query( col ).$eq("israd", true).count();
		var origNestedBool = mongo.query( col ).$eq("types.israd", true).count();
		var origFloats = mongo.query( col ).$eq("floats",1.3).count();
		var origNestedFloats = mongo.query( col ).$eq("types.floats",1.3).count();
		var origString = mongo.query( col ).$eq("address.street", "123 big top lane").count();

		mongo.save( doc, col );

		var newNums = mongo.query( col ).$eq("number", types.number).count();
		var newNestedNums = mongo.query( col ).$eq("types.number", types.number).count();
		var newBool = mongo.query( col ).$eq("israd", true).count();
		var newNestedBool = mongo.query( col ).$eq("types.israd", true).count();
		var newFloats = mongo.query( col ).$eq("floats",1.3).count();
		var newNestedFloats = mongo.query( col ).$eq("types.floats",1.3).count();
		var newString = mongo.query( col ).$eq("address.street", "123 big top lane").count();

		assertEquals( origNums+1, newNums );
		assertEquals( origNestedNums+1, newNestedNums );
		assertEquals( origBool+1, newBool );
		assertEquals( origNestedBool+1, newNestedBool );
		assertEquals( origFloats+1, newFloats );
		assertEquals( origNestedFloats+1, newNestedFloats );
		assertEquals( origString+1, newString );

	}

	/**
	*	Confirm getLastError works and mongo has not changed its response.
	*/
	function getLastError_should_return_error_when_expected()
	{
		var jColl = mongo.getMongoDBCollection(col, mongoConfig);
		var mongoUtil = mongo.getMongoUtil();

		// Create people to steal an id from
		createPeople();

		// Get the result of the last activity from CreatePeople()
		local.lastActivity = mongo.getLastError();
		assertFalse( structKeyExists(local.lastActivity, "code"), "code key should not exist when no error is present");

		local.peeps = mongo.query(collectionName=col).find(limit="1").asArray();
		assertFalse(
			arrayIsEmpty(local.peeps)
			,'Some people should have been returned.'
		);


		// Let's duplicate the record.
		local.person = local.peeps[1];
		jColl.insert([mongoUtil.toMongo(local.person)]);

		// Get the result of the last activity
		local.lastActivity = mongo.getLastError();

		// Confirm we did try to duplicate an id.
		assert(
			 structKeyExists(local.lastActivity,'code')
			,'Mongo should be upset a record was duplicated. Check the test.'
		);
	}

	function whatsUpWithCFBasicDBObject(){
		var dude = {name="TheDude", abides=true, age=100};
		var dboDude = mongo.getMongoUtil().toMongo( dude );
		var mongoDBO = javaloaderFactory.getObject("com.mongodb.BasicDBObject");
		mongoDBO.putAll(dude);
		debug( isStruct(dboDude) );
		debug( isObject(dboDude) );
		debug( getMetadata(dboDude).getSimpleName() );


		debug( dude.toString() );
		debug( mongoDBO.toString() );
		debug( dboDude.toString() );
	}

 </cfscript>

 <!--- include these here so they don't mess up the line numbering --->
 <cfinclude template="commonTestMixins.cfm">

</cfcomponent>

