using DraftAssistant.Infrastructure.Storage;
using Xunit;

namespace DraftAssistant.Tests;

public sealed class SamePatchTests
{
    [Theory]
    [InlineData("7.42", "7.42", true)]
    [InlineData("7.42a", "7.42", true)]
    [InlineData("7.41e", "7.42", false)]   // STRATZ ещё не завёл новый патч
    [InlineData("7.420", "7.42", false)]
    [InlineData("", "7.42", false)]
    [InlineData("7.42a", "", false)]
    public void MatchesPatchWithOptionalLetter(string gameVersion, string patch, bool expected) =>
        Assert.Equal(expected, DataFiles.SamePatch(gameVersion, patch));
}
