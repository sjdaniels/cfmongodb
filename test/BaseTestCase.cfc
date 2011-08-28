<cfcomponent output="false" extends="mxunit.framework.TestCase">

	<cfset dbName = "cfmongodb_tests">
	<cfset factoryType = "cfmongodb.core.JavaloaderFactory">

	<cffunction name="beforeTests">
		<cfset mongoConfig = getMongoConfig()>
	</cffunction>

	<cffunction name="getMongoConfig" access="private">
		<cfargument name="dbName" default="#variables.dbName#">

		<cfset var factory = createObject('component', factoryType).init()>
		<cfreturn createObject('component', 'cfmongodb.core.MongoConfig').init(dbName=arguments.dbName, mongoFactory=factory)>
	</cffunction>

	<cffunction name='thisTestUsesCorrectFactory'>
		<cfset debug( factoryType )>
		<cfset debug( getMetadata(mongoConfig.getMongoFactory()).fullName )>
		<cfset assertEquals( factoryType, getMetadata(mongoConfig.getMongoFactory()).fullName )>
	</cffunction>

</cfcomponent>