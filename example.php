<?php

// -----------------------------
// CONFIGURE THIS
// -----------------------------
$initialUrl = ""; 
// The response should be plain text containing the .m3u8 playlist URL

// Fetch the contents of the initial URL
$playlistUrl = trim(file_get_contents($initialUrl));

// Modify URL parameters
function addPrefixParams($url) {
    $parsed = parse_url($url);

    // If no query parameters, nothing to do
    if (!isset($parsed['query'])) {
        return $url;
    }

    parse_str($parsed['query'], $params);

    // Duplicate params with -PREFIX
    foreach ($params as $key => $value) {
        $params[$key . "-PREFIX"] = $value;
    }

    // Rebuild URL
    $newQuery = http_build_query($params);

    $rebuilt =
        (isset($parsed['scheme']) ? $parsed['scheme'] . "://" : "") .
        (isset($parsed['host'])   ? $parsed['host'] : "") .
        (isset($parsed['port'])   ? ":" . $parsed['port'] : "") .
        (isset($parsed['path'])   ? $parsed['path'] : "") .
        "?" . $newQuery;

    return $rebuilt;
}

$modifiedUrl = addPrefixParams($playlistUrl);

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>PHP Version - VideoJS HLS Loader</title>

    <link href="https://vjs.zencdn.net/8.5.2/video-js.css" rel="stylesheet">
    <style>
        body { font-family: sans-serif; margin: 20px; }
    </style>
</head>

<body>
    <h2>PHP Version - HLS Player</h2>

    <p><strong>Original generated playlist URL:</strong><br><?php echo $playlistUrl; ?></p>
    <p><strong>Modified playlist URL:</strong><br><?php echo $modifiedUrl; ?></p>

    <video
        id="videoPlayer"
        class="video-js vjs-default-skin"
        width="640"
        height="360"
        controls
    ></video>

    <script src="https://vjs.zencdn.net/8.5.2/video.min.js"></script>

    <script>
        const player = videojs("videoPlayer");

        player.src({
            src: "<?php echo $modifiedUrl; ?>",
            type: "application/vnd.apple.mpegurl"
        });

        player.play();
    </script>
</body>
</html>
