<!---run load.cfm to get the data that these will use! --->
<!--- pass forceLoad=true in the URL to force new data --->
<cfinclude template="load.cfm">

<cfinclude template="../initMongo.cfm">

<cfscript>
	collection = "geoexamples";
	dbCol = mongo.getDBCollection( collection );

	try {
		//only need to do this once, but here for illustration
		dbCol.dropIndexes();
		indexes = dbCol.ensureGeoIndex("LOC");
		writeDump(indexes);

		//as of this writing, you can perform geo queries like so:
		nearResult = dbCol.query().add( "LOC", {"$near" = [38,-85]} ).find(limit=10);
		writeDump( var = nearResult.asArray(), label = "$near result" );
	}
		catch(Any e){
		writeDump(e);
	}

	mongo.close();
</cfscript>
