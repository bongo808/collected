import Foundation

enum GPXExporter {
    static func makeGPX(for ride: Ride) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="BikeTracker"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(ride.name))</name>
            <time>\(iso.string(from: ride.startDate))</time>
          </metadata>
          <trk>
            <name>\(escape(ride.name))</name>
            <type>cycling</type>
            <trkseg>

        """

        for p in ride.points {
            xml += """
                  <trkpt lat="\(p.latitude)" lon="\(p.longitude)">
                    <ele>\(p.altitude)</ele>
                    <time>\(iso.string(from: p.timestamp))</time>
                  </trkpt>

            """
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>
        """
        return xml
    }

    static func writeGPX(for ride: Ride) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ride-\(ride.id.uuidString).gpx")
        try makeGPX(for: ride).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
