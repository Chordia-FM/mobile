package fm.chordia.mobile

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity, not FlutterActivity: it keeps the Flutter engine attached to the running
// audio service, so the activity can be destroyed and recreated without tearing down playback.
class MainActivity : AudioServiceActivity()
