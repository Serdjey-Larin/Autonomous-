package com.example.autonomouseye;

import android.content.Context;
import android.util.Log;

import info.mqtt.android.service.MqttAndroidClient;
import org.eclipse.paho.client.mv3.IMqttActionListener;
import org.eclipse.paho.client.mv3.IMqttDeliveryToken;
import org.eclipse.paho.client.mv3.IMqttToken;
import org.eclipse.paho.client.mv3.MqttCallbackExtended;
import org.eclipse.paho.client.mv3.MqttConnectOptions;
import org.eclipse.paho.client.mv3.MqttException;
import org.eclipse.paho.client.mv3.MqttMessage;

import java.util.UUID;

public class MqttManager {

    private static final String TAG = "MqttManager";

    private final Context context;
    private final String brokerUrl;
    private final String clientId;
    private MqttAndroidClient client;
    private MqttListener listener;

    public interface MqttListener {
        void onConnected();
        void onDisconnected();
        void onMessageReceived(String topic, String payload);
        void onError(String error);
    }

    public MqttManager(Context context, String brokerUrl) {
        this.context = context;
        this.brokerUrl = brokerUrl;
        this.clientId = "Eye_" + UUID.randomUUID().toString().substring(0, 8);
        this.client = new MqttAndroidClient(context, brokerUrl, clientId);
    }

    public void setListener(MqttListener listener) {
        this.listener = listener;
    }

    public void connect(String username, String password) {
        MqttConnectOptions options = new MqttConnectOptions();
        options.setAutomaticReconnect(true);
        options.setCleanSession(true);
        options.setConnectionTimeout(30);
        options.setKeepAliveInterval(60);
        if (username != null && !username.isEmpty()) {
            options.setUserName(username);
            options.setPassword(password.toCharArray());
        }

        client.setCallback(new MqttCallbackExtended() {
            @Override
            public void connectComplete(boolean reconnect, String serverURI) {
                Log.d(TAG, "Connected to " + serverURI);
                if (listener != null) listener.onConnected();
            }

            @Override
            public void connectionLost(Throwable cause) {
                Log.e(TAG, "Connection lost", cause);
                if (listener != null) listener.onDisconnected();
            }

            @Override
            public void messageArrived(String topic, MqttMessage message) {
                String payload = new String(message.getPayload());
                Log.d(TAG, "Message on " + topic + ": " + payload);
                if (listener != null) listener.onMessageReceived(topic, payload);
            }

            @Override
            public void deliveryComplete(IMqttDeliveryToken token) {
            }
        });

        try {
            client.connect(options, null, new IMqttActionListener() {
                @Override
                public void onSuccess(IMqttToken asyncActionToken) {
                    Log.d(TAG, "Connect success");
                }

                @Override
                public void onFailure(IMqttToken asyncActionToken, Throwable exception) {
                    Log.e(TAG, "Connect failed", exception);
                    if (listener != null) listener.onError("Connect failed: " + exception.getMessage());
                }
            });
        } catch (MqttException e) {
            Log.e(TAG, "MqttException", e);
            if (listener != null) listener.onError(e.getMessage());
        }
    }

    public void subscribe(String topic, int qos) {
        try {
            client.subscribe(topic, qos, null, new IMqttActionListener() {
                @Override
                public void onSuccess(IMqttToken asyncActionToken) {
                    Log.d(TAG, "Subscribed to " + topic);
                }

                @Override
                public void onFailure(IMqttToken asyncActionToken, Throwable exception) {
                    Log.e(TAG, "Subscribe failed", exception);
                }
            });
        } catch (MqttException e) {
            Log.e(TAG, "Subscribe MqttException", e);
        }
    }

    public void publish(String topic, String payload, int qos, boolean retained) {
        try {
            MqttMessage message = new MqttMessage(payload.getBytes());
            message.setQos(qos);
            message.setRetained(retained);
            client.publish(topic, message);
        } catch (MqttException e) {
            Log.e(TAG, "Publish MqttException", e);
        }
    }

    public void disconnect() {
        try {
            if (client != null && client.isConnected()) {
                client.disconnect();
            }
        } catch (MqttException e) {
            Log.e(TAG, "Disconnect error", e);
        }
    }

    public boolean isConnected() {
        return client != null && client.isConnected();
    }
}
