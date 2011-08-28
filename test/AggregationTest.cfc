<cfcomponent output="false" extends="BaseTestCase">
<cfscript>
import cfmongodb.core.*;


	function setUp(){
		mongo = createObject('component','cfmongodb.core.Mongo').init(mongoConfig);
		col = 'articles';
		dbCol = mongo.getDBCollection( col );

		commonSetUp();
	}

	function tearDown(){
		dbCol.remove({});
		commonTearDown();
	}

	function group_should_aggregate(){
		var articles = createArticles();
		dbCol.saveAll(articles);

		var reduce = "
			function( obj, agg ){
				agg.TOTAL++;
			}
		";

		var finalize = "
			function( out ){
				out.AVG = out.TOTAL / #arrayLen(articles)#
			}
		";

		var groups = dbCol.group(
			keys="STATUS",
			initial={TOTAL=0},
			reduce=reduce,
			finalize=finalize
		);

		debug(groups);

		//all these assertions are based on the articles we created below. This is static so that the tests are determinant
		assertEquals( 4, arrayLen(groups), "should have 4 groups because we had 4 different statuses");

		assertEquals( "P", groups[1].status);
		assertEquals( 2, groups[1].total );
		assertEquals( 0.2, groups[1].avg );
		assertEquals( "R", groups[2].status );
		assertEquals( 3, groups[2].total );
		assertEquals( 0.3, groups[2].avg );
		assertEquals( "S", groups[3].status );
		assertEquals( 3, groups[3].total );
		assertEquals( 0.3, groups[3].avg );
		assertEquals( "C", groups[4].status );
		assertEquals( 2, groups[4].total );
		assertEquals( 0.2, groups[4].avg );

	}

	/**
	* @mxunit:expectedException GroupException
	*/
	function group_should_rethrow_mongo_error_when_present(){
		var reduce = "
			function( obj, agg ){
		";

		var groups = dbCol.group(
			keys="STATUS",
			initial={TOTAL=0},
			reduce=reduce
		);

	}

	function mapReduce_should_aggregate(){
		var articles = createArticles();
		dbCol.saveAll(articles);

		var map = "
			function(){
				var totalTopics = this.TAGS.length;
				var i = 0;
				this.TAGS.forEach(
					function(z){
						emit( z, {count: 1} );
					}
				);
			}
		";
		var reduce = "
			function(key, emits){
				var total = 0;

				for( var i in emits ){
					total += emits[i].count;
				}
				return {count: total};
			}
		";
		var finalize = "
			function( key, value ){
				value.rank = value.count / inputcount;
				value.processed = processed;
				return value;
			}
		";
		var scope = {"inputcount" = arrayLen(articles), "processed" = now()};
		var result = dbCol.mapReduce( map=map, reduce=reduce, outputTarget="article_topic_rank", options={"scope"=scope, "finalize"=finalize} );
		//debug(result.asArray());
		assertEquals( 4, arrayLen(result.asArray()), "should have had 4 elements because there were 4 different tags" );

		var sorted = mongo.getDBCollection("article_topic_rank").find(sort={"value.count"=-1});
		var sortedResult = sorted.asArray();
		debug(sortedResult);
		assertEquals(10, sortedResult[1]["value"]["count"] );
		assertEquals(1, sortedResult[1]["value"]["rank"] );
		assertEquals(2, sortedResult[4]["value"]["count"] );
		assertEquals(0.2, sortedResult[4]["value"]["rank"] );
	}

	/**
	* @mxunit:expectedException MapReduceException
	*/
	function mapReduce_should_rethrow_mongo_error_when_present(){
		var map = "
			function(){
				this.HIMOM.forEach(
					function(z){
						emit( z, {count: 1} );

				);
			}
		";
		var reduce = "
			function(key, emits){
				var total = 0;

				for( var i in emits ){
					total += emits[i].count;
				}
				return {count: total};
			}
		";

		var result = dbCol.mapReduce( map=map, reduce=reduce, outputTarget="map_reduce_error" );
		debug(result);
	}


	/**
	* creates a dataset to work with both group and mapReduce
	*/
	private function createArticles(){
		var articles = [];
		var tags = "";
		var i = 1;
		var status = "";

		for(i=1; i <= 10; i++){

			tags = i <= 2 ? ["one","two","three","four"]
				: i > 2 && i <= 5 ? ["one","two","three"]
				: i > 5 && i <= 8 ? ["one","two"]
				: ["one"];
			//arbitrary letters
			status = i <= 2 ? "P"
				: i > 2 && i <= 5 ? "R"
				: i > 5 && i <= 8 ? "S"
				: "C";

			arrayAppend( articles,
				{
					NAME = "article_#i#",
					N = i,
					TAGS = tags,
					STATUS = status
				}
			);
		}
		return articles;
	}
 </cfscript>

 <!--- include these here so they don't mess up the line numbering --->
 <cfinclude template="commonTestMixins.cfm">

</cfcomponent>

