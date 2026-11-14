using Velopack;

namespace DraftAssistant.Presentation;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Обрабатывает события установки/обновления/удаления (создание ярлыков и т.п.)
        // и сразу завершает процесс, если запущен установщиком. Должно идти первым.
        VelopackApp.Build().Run();

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}
