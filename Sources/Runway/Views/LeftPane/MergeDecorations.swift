import SwiftUI

struct MergeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Circle 1: cx="4.5" cy="3.5" r="1.75"
        path.addEllipse(in: CGRect(x: 4.5 - 1.75, y: 3.5 - 1.75, width: 3.5, height: 3.5))
        
        // Circle 2: cx="4.5" cy="12.5" r="1.75"
        path.addEllipse(in: CGRect(x: 4.5 - 1.75, y: 12.5 - 1.75, width: 3.5, height: 3.5))
        
        // Circle 3: cx="12.5" cy="8.5" r="1.75"
        path.addEllipse(in: CGRect(x: 12.5 - 1.75, y: 8.5 - 1.75, width: 3.5, height: 3.5))
        
        // Path: d="m4.75 10.25v-4.5c1 2 2 3 5.5 3"
        path.move(to: CGPoint(x: 4.75, y: 10.25))
        path.addLine(to: CGPoint(x: 4.75, y: 5.75))
        path.addCurve(
            to: CGPoint(x: 10.25, y: 8.75),
            control1: CGPoint(x: 5.75, y: 7.75),
            control2: CGPoint(x: 6.75, y: 8.75)
        )
        
        let scaleX = rect.width / 16.0
        let scaleY = rect.height / 16.0
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        return path.applying(transform)
    }
}

struct MergeCardDecorations: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            
            ZStack(alignment: .top) {
                // Icon 1: far left, small/medium, low opacity
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.03), style: StrokeStyle(lineWidth: 1.5 * (14.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                    .position(x: width * 0.02, y: 8)
                
                // Icon 2: large, higher opacity, sticking out top
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.06), style: StrokeStyle(lineWidth: 1.5 * (36.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 36, height: 36)
                    .position(x: width * 0.12, y: 6)
                
                // Icon 3: small, low opacity, centered-left
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.04), style: StrokeStyle(lineWidth: 1.5 * (10.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 10)
                    .position(x: width * 0.25, y: 4)
                
                // Icon 4: tiny, low opacity, near center
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.03), style: StrokeStyle(lineWidth: 1.5 * (8.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 8)
                    .position(x: width * 0.50, y: 5)
                
                // Icon 5: small/medium, centered-right
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.045), style: StrokeStyle(lineWidth: 1.5 * (12.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 12)
                    .position(x: width * 0.75, y: 7)
                
                // Icon 6: large, high opacity
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.08), style: StrokeStyle(lineWidth: 1.5 * (32.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 32, height: 32)
                    .position(x: width * 0.86, y: 8)
                
                // Icon 7: medium/small, far right
                MergeIconShape()
                    .stroke(FeedRow.purple.opacity(0.05), style: StrokeStyle(lineWidth: 1.5 * (16.0 / 16.0), lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                    .position(x: width * 0.97, y: 6)
            }
        }
        .allowsHitTesting(false)
    }
}
