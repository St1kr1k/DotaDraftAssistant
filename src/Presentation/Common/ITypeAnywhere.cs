namespace DraftAssistant.Presentation.Common;

/// <summary>Страница, которая принимает ввод с клавиатуры, даже если поле поиска не в фокусе (как сетка героев в Доте).</summary>
public interface ITypeAnywhere
{
    void TypeText(string text);
    void TypeBackspace();
    void TypeEscape();
}
