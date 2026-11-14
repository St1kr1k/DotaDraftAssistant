using System.Globalization;
using System.Windows.Data;

namespace DraftAssistant.Presentation.Common;

/// <summary>Число × коэффициент из ConverterParameter (например, высота плитки = ширина × 0.75).</summary>
public sealed class RatioConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        double v = value is double d ? d : 0;
        double k = double.TryParse(parameter as string, NumberStyles.Float, CultureInfo.InvariantCulture, out var p) ? p : 1;
        return Math.Max(0, v * k);
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
