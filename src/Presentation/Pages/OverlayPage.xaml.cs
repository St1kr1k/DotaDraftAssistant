using System.Windows.Controls;

namespace DraftAssistant.Presentation.Pages;

public partial class OverlayPage : UserControl
{
    public OverlayPage(OverlaySettingsViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
