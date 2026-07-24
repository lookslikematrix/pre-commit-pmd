package example;

public class Greeter {
    public String greet(String name) {
        String unused = "never used";
        if (name == null) return null;
        return "hello, " + name;
    }
}
