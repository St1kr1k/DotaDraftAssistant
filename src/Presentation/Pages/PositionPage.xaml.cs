using System.Windows.Controls;

namespace DraftAssistant.Presentation.Pages;

public partial class PositionPage : UserControl
{
    public PositionPage(PositionViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
