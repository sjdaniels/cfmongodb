package net.marcesher;

public class MongoDBOperationOnlyTyper implements Typer {

	private final static Typer instance = new MongoDBOperationOnlyTyper();
	
	public static Typer getInstance(){
		return instance;
	}
	
	@Override
	public Object toJavaType(Object val) {
		return val;
	}

}
