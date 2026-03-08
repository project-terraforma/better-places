import controllers.app_controller;
import std;

void main(string[] args) {
    scope app = new AppController(args, "santa_cruz");
    app.load().run();
}
