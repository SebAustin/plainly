import type { DeviceModelStatus } from '../../core/routing'
import './status.css'

interface StatusBarProps {
  deviceModel: DeviceModelStatus
  downloadProgress: number | null
  isOnline: boolean
  onDownload: () => void
}

const DEVICE_LABEL: Record<DeviceModelStatus, string> = {
  available: 'On-device model ready',
  downloadable: 'On-device model not installed',
  downloading: 'Installing on-device model',
  unavailable: 'No on-device model in this browser',
}

export function StatusBar({ deviceModel, downloadProgress, isOnline, onDownload }: StatusBarProps) {
  const percent = downloadProgress === null ? null : Math.round(downloadProgress * 100)
  return (
    <ul className="status" aria-label="Where your letters can be read">
      <li className={`status-item status-${deviceModel}`}>
        <span className="status-dot" aria-hidden="true" />
        {DEVICE_LABEL[deviceModel]}
        {percent !== null && ` · ${percent}%`}
        {deviceModel === 'downloadable' && (
          <button type="button" className="link-button" onClick={onDownload}>
            Install
          </button>
        )}
      </li>
      <li className={`status-item ${isOnline ? 'status-online' : 'status-offline'}`}>
        <span className="status-dot" aria-hidden="true" />
        {isOnline ? 'Cloud reachable' : 'Offline'}
      </li>
    </ul>
  )
}
