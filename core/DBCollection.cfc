<cfcomponent>

<cfscript>
	variables.collectionName = "";
	variables.mongo = "";
	variables.collection = "";

	function init( collectionName, mongo ){
		structAppend( variables, arguments );
		variables.collection = getMongoDBCollection( collectionName );
		variables.mongoUtil = mongo.getMongoUtil();
		variables.mongoConfig = mongo.getMongoConfig();
		return this;
	}

	/**
	* Get the underlying Java driver's DB object
	*/
	function getMongoDB(){
		return variables.mongo.getMongo().getDb( variables.mongo.getMongoConfig().getDBName() );
	}

	/**
	* Get the underlying Java driver's DBCollection object for the given collection
	*/
	function getMongoDBCollection( collectionName ){
		var jMongoDB = getMongoDB();
		return jMongoDB.getCollection( collectionName );
	}

	/**
	* For simple mongo _id searches, use findById(), like so:

	  byID = collection.findById( url.personId, collection );
	*/
	function findById( id ){
		var result = collection.findOne( mongoUtil.newIDCriteriaObject( id ) );
		return mongoUtil.toCF( result );
	}

	/**
	* Run a query against MongoDB.
	  Query returns a SearchBuilder object, which you'll call functions on.
	  Finally, you'll use various "execution" functions on the SearchBuilder to get a SearchResult object,
	  which provides useful functions for working with your results.

	  kidSearch = collection.query().between("KIDS.AGE", 2, 30).search();
	  writeDump( kidSearch.asArray() );

	  See gettingstarted.cfm for many examples
	*/
	function query(){
	   return new SearchBuilder( collectionName, getMongoDB(mongoConfig) , mongoUtil );
	}

	/**
	* Runs mongodb's distinct() command. Returns an array of distinct values
	*
	  distinctAges = collection.distinct( "KIDS.AGE", "people" );
	*/
	function distinct(string key, string collectionName ){
		return collection.distinct( key );
	}

	/**
	* So important we need to provide top level access to it and make it as easy to use as possible.

	FindAndModify is critical for queue-like operations. Its atomicity removes the traditional need to synchronize higher-level methods to ensure queue elements only get processed once.

	http://www.mongodb.org/display/DOCS/findandmodify+Command

	This function assumes you are using this to *apply* additional changes to the "found" document. If you wish to overwrite, pass overwriteExisting=true. One bristles at the thought

	*/
	function findAndModify(struct query, struct fields, any sort, boolean remove=false, struct update, boolean returnNew=true, boolean upsert=false, boolean applySet=true ){
		// Confirm our complex defaults exist; need this chunk of muck because CFBuilder 1 breaks with complex datatypes in defaults
		local.argumentDefaults = {sort={"_id"=1},fields={}};
		for(local.k in local.argumentDefaults)
		{
			if (!structKeyExists(arguments, local.k))
			{
				arguments[local.k] = local.argumentDefaults[local.k];
			}
		}

		//must apply $set, otherwise old struct is overwritten
		if( applySet ){
			update = { "$set" = mongoUtil.toMongo(update)  };
		}
		if( not isStruct( sort ) ){
			sort = mongoUtil.createOrderedDBObject(sort);
		} else {
			sort = mongoUtil.toMongo( sort );
		}

		var updated = collection.findAndModify(
			mongoUtil.toMongo(query),
			mongoUtil.toMongo(fields),
			sort,
			remove,
			mongoUtil.toMongo(update),
			returnNew,
			upsert
		);
		if( isNull(updated) ) return {};

		return mongoUtil.toCF(updated);
	}

	/**
	* Executes Mongo's group() command. Returns an array of structs.

	  usage, including optional 'query':

	  result = collection.group( "tasks", "STATUS,OWNER", {TOTAL=0}, "function(obj,agg){ agg.TOTAL++; }, {SOMENUM = {"$gt" = 5}}" );

	  See examples/aggregation/group.cfm for detail
	*/
	function group( keys, initial, reduce, query, keyf="", finalize="" ){

		if (!structKeyExists(arguments, 'query'))
		{
			arguments.query = {};
		}

		var dbCommand =
			{ "group" =
				{"ns" = collectionName,
				"key" = mongoUtil.createOrderedDBObject(keys),
				"cond" = query,
				"initial" = initial,
				"$reduce" = trim(reduce),
				"finalize" = trim(finalize)
				}
			};
		if( len(trim(keyf)) ){
			structDelete(dbCommand.group,"key");
			dbCommand.group["$keyf"] = trim(keyf);
		}
		var result = getMongoDB().command( mongoUtil.toMongo(dbCommand) );
		return result["retval"];
	}


	/**
	* Executes Mongo's mapReduce command. Returns a MapReduceResult object

	  basic usage:

	  result = collection.mapReduce( collectionName="tasks", map=map, reduce=reduce );


	  See examples/aggregation/mapReduce for detail
	*/
	function mapReduce( map, reduce, outputTarget, outputType="REPLACE", query, options  ){

		// Confirm our complex defaults exist; need this hunk of muck because CFBuilder 1 breaks with complex datatypes as defaults
		var argumentDefaults = {
			 query={}
			,options={}
		};
		var k = "";
		for(k in argumentDefaults) {
			if (!structKeyExists(arguments, k))
			{
				arguments[k] = local.argumentDefaults[k];
			}
		}

		var optionDefaults = {"sort"={}, "limit"="", "scope"={}, "verbose"=true};
		structAppend( optionDefaults, arguments.options );
		if( structKeyExists(optionDefaults, "finalize") ){
			optionDefaults.finalize = trim(optionDefaults.finalize);
		}

		var out = {"#lcase(outputType)#" = outputTarget};
		if(outputType eq "inline"){
			out = {"inline" = 1};
		} else if (outputType eq "replace") {
			out = outputTarget;
		}

		var dbCommand = mongoUtil.createOrderedDBObject(
			[
				{"mapreduce"=collectionName}, {"map"=trim(map)}, {"reduce"=trim(reduce)}, {"query"=query}, {"out"=out}
			] );

		dbCommand.putAll(optionDefaults);
		var commandResult = getMongoDB().command( dbCommand );

		var searchResult = this.query( commandResult["result"] ).search();
		var mapReduceResult = createObject("component", "MapReduceResult").init(dbCommand, commandResult, searchResult, mongoUtil);
		return mapReduceResult;
	}

	/**
	*  Saves a struct into the collection; Returns the newly-saved Document's _id; populates the struct with that _id

		person = {name="bill", badmofo=true};
		collection.save( person, "coolpeople" );
	*/
	function save( struct doc ){
	   if( structKeyExists(doc, "_id") ){
	       update( doc = doc );
	   } else {
		   var dbObject =  mongoUtil.toMongo(doc);
		   collection.insert( [dbObject] );
		   doc["_id"] =  dbObject.get("_id");
	   }
	   return doc["_id"];
	}

	/**
	* Saves an array of structs into the collection. Can also save an array of pre-created CFBasicDBObjects

		people = [{name="bill", badmofo=true}, {name="marc", badmofo=true}];
		collection.saveAll( people, "coolpeople" );
	*/
	function saveAll( array docs ){
		if( arrayIsEmpty(docs) ) return docs;

		var i = 1;
		if( mongoUtil.isCFBasicDBObject( docs[1] ) ){
			collection.insert( docs );
		} else {
			var total = arrayLen(docs);
			var allDocs = [];
			for( i=1; i LTE total; i++ ){
				arrayAppend( allDocs, mongoUtil.toMongo(docs[i]) );
			}
			collection.insert(allDocs);
		}
		return docs;
	}

	/**
	* Updates a document in the collection.

	The "doc" argument will either be an existing Mongo document to be updated based on its _id, or it will be a document that will be "applied" to any documents that match the "query" argument

	To update a single existing document, simply pass that document and update() will update the document by its _id:
	 person = person.findById(url.id);
	 person.something = "something else";
	 collection.update( person, "people" );

	To update a document by a criteria query and have the "doc" argument applied to a single found instance:
	update = {STATUS = "running"};
	query = {STATUS = "pending"};
	collection.update( update, "tasks", query );

	To update multiple documents by a criteria query and have the "doc" argument applied to all matching instances, pass multi=true
	collection.update( update, "tasks", query, false, true )

	Pass upsert=true to create a document if no documents are found that match the query criteria
	*/
	function update( doc, query, upsert=false, multi=false, applySet=true ){

		if ( !structKeyExists(arguments, 'query') ){
			arguments.query = {};
		}

	   if( structIsEmpty(query) ){
		  query = mongoUtil.newIDCriteriaObject(doc['_id'].toString());
		  var dbo = mongoUtil.toMongo(doc);
	   } else{
	   	  query = mongoUtil.toMongo(query);
		  var keys = structKeyList(doc);
		  if( applySet ){
		  	doc = { "$set" = mongoUtil.toMongo(doc)  };
		  }
	   }
	   var dbo = mongoUtil.toMongo(doc);
	   collection.update( query, dbo, upsert, multi );
	}

	/**
	* Remove one or more documents from the collection.

	  If the document has an "_id", this will remove that single document by its _id.

	  Otherwise, "doc" is treated as a "criteria" object. For example, if doc is {STATUS="complete"}, then all documents matching that criteria would be removed.

	  pass an empty struct to remove everything from the collection: collection.remove({}, collection);
	*/
	function remove(doc, collectionName ){
		if( structKeyExists(doc, "_id") ){
			return removeById( doc["_id"] );
		}
	   var dbo = mongoUtil.toMongo(doc);
	   var writeResult = collection.remove( dbo );
	   return writeResult;
	}

	/**
	* Convenience for removing a document from the collection by the String representation of its ObjectId

		collection.removeById(url.id);
	*/
	function removeById( id ){
		return collection.remove( mongoUtil.newIDCriteriaObject(id) );
	}

	/**
	* The array of fields can either be
	a) an array of field names. The sort direction will be "1"
	b) an array of structs in the form of fieldname=direction. Eg:

	[
		{lastname=1},
		{dob=-1}
	]

	*/
	public array function ensureIndex(array fields, unique=false ){
	 	var pos = 1;
	 	var doc = {};
		var indexName = "";
		var fieldName = "";

	 	for( pos = 1; pos LTE arrayLen(fields); pos++ ){
			if( isSimpleValue(fields[pos]) ){
				fieldName = fields[pos];
				doc[ fieldName ] = 1;
			} else {
				fieldName = structKeyList(fields[pos]);
				doc[ fieldName ] = fields[pos][fieldName];
			}
			indexName = listAppend( indexName, fieldName, "_");
	 	}

	 	var dbo = mongoUtil.toMongo( doc );
	 	collection.ensureIndex( dbo, "_#indexName#_", unique );

	 	return getIndexes(collectionName, mongoConfig);
	}

	/**
	* Ensures a "2d" index on a single field. If another 2d index exists on the same collection, this will error
	*/
	public array function ensureGeoIndex( field, min="", max="" ){
		var doc = { "#arguments.field#" = "2d" };
		var options = {};
		if( isNumeric(arguments.min) and isNumeric(arguments.max) ){
			options = {"min" = arguments.min, "max" = arguments.max};
		}
		//need to do this bit of getObject ugliness b/c the CFBasicDBObject will convert "2d" to a double. whoops.
		collection.ensureIndex( mongoUtil.getMongoFactory().getObject("com.mongodb.BasicDBObject").init(doc), mongoUtil.toMongo(options) );
		return getIndexes( collectionName, mongoConfig );
	}

	/**
	* Returns an array with information about all of the indexes for the collection
	*/
	public array function getIndexes(){
		return collection.getIndexInfo().toArray();
	}

	/**
	* Drops all indexes from the collection
	*/
	public array function dropIndexes( ){
		collection.dropIndexes();
		return getIndexes();
	}


</cfscript>
</cfcomponent>