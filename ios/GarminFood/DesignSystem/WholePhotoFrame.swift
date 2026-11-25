// WholePhotoFrame.swift
//
// A photo shown WHOLE in a frame of one fixed height, whatever its shape: a
// tall phone wallpaper and a wide meme occupy the same box, so a card never
// jumps in height from day to day and nothing is ever cropped. The picture is
// fitted (scaledToFit) and centred; the space it leaves is filled with a
// blurred, dimmed copy of the same picture instead of bare bars.
//
// Used by the daily motivation card (add-daily-motivation) and the partner
// theme's love card (add-partner-love-theme). Callers set the accessibility
// label (or hide it). The same file, byte for byte,
// is on both branches so they merge without a conflict.

import SwiftUI
import UIKit

struct WholePhotoFrame: View {
    let image: UIImage
    var height: CGFloat = 380

    var body: some View {
        // The overlays take the size of the clear base, so the blurred
        // fill (which overflows) can never widen or heighten the frame.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .opacity(0.45)
            }
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
