import Foundation

@MainActor
extension Checks {
    func checkNotifications() async throws {
        try await run("notification inbox and registration keep authentication and private preview defaults") {
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ContractTransport.self]
            let api=MessageAPI(base:URL(string:"https://contract.invalid")!,token:"chat_notification_fixture",configuration:config)
            let device=UUID().uuidString.lowercased();var calls=0
            ContractTransport.install {request in
                try self.expect(request.value(forHTTPHeaderField:"Authorization")=="Bearer chat_notification_fixture","notification request omitted authorization")
                let path=request.url!.path;calls+=1
                if path.hasSuffix("/status"){return (200,Data(#"{"enabled":true,"apns":false,"vivo":false,"userId":"user-1"}"#.utf8))}
                if path=="/api/device-messages/notifications" {
                    let items=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
                    try self.expect(items.contains {$0.name=="deviceId"&&$0.value==device},"notification device changed")
                    try self.expect(items.contains {$0.name=="preview"&&$0.value=="false"},"private preview default changed")
                    return (200,Data(#"{"events":[],"nextAfter":42,"hasMore":false}"#.utf8))
                }
                try self.expect(request.httpMethod=="POST","notification mutation was not POST")
                return (200,Data(#"{"registered":true,"removed":true}"#.utf8))
            }
            let status=try await api.notificationStatus();try expect(status.userId=="user-1" && !status.apns,"notification status mixed account and transport state")
            let first=try await api.notifications(device:device,after:nil,preview:false)
            try expect(first.events.isEmpty&&first.nextAfter==42,"notification baseline replayed history")
            _ = try await api.notifications(device:device,after:42,preview:false)
            try await api.registerNotifications(PushRegistration(deviceId:device,platform:"ios",provider:"local",token:"",environment:"development",enabled:true,preview:false,activeRoom:nil))
            try await api.removeNotifications(device:device)
            try expect(calls==5,"notification protocol made an unexpected request")
        }
    }
}
