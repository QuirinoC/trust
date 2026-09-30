/// Color backing shared by preset avatar artwork in the app and picker.
public enum AvatarArtworkPalette {
    public static func backingHex(isDarkAppearance: Bool) -> UInt32 {
        isDarkAppearance ? 0x334055 : 0xFCFAF2
    }
}
