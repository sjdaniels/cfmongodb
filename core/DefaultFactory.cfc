<cfcomponent output="false" extends="AbstractFactory">

	<cffunction name="getObject" output="false" access="public" returntype="any" hint="">
    	<cfargument name="path" type="string" required="true"/>
		<cfreturn createObject("java", path)>
    </cffunction>

</cfcomponent>